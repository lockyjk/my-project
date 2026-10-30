"""Crawl every configured source once: fetch, parse, enrich, store."""

from __future__ import annotations

import json
import logging
import re
import tomllib
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .enrich import enrich
from .fetch import Fetcher
from .models import Article
from .parse import PARSERS, parse_feed
from .store import Store

log = logging.getLogger(__name__)

SEC_TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
_SEC_TITLE = re.compile(r"^\S+ - (.+?) \((\d{10})\)")


@dataclass
class Config:
    user_agent: str
    database: str = "news.db"
    poll_seconds: int = 60
    min_host_interval: float = 2.0
    max_age_hours: float = 24
    half_life_minutes: float = 60
    watchlist: list[str] = field(default_factory=list)
    aliases: dict[str, str] = field(default_factory=dict)
    alerts: dict = field(default_factory=dict)
    sources: list[dict] = field(default_factory=list)
    bot: dict = field(default_factory=dict)
    filter: dict = field(default_factory=dict)
    risk: dict = field(default_factory=dict)

    @classmethod
    def load(cls, path: str | Path) -> Config:
        data = tomllib.loads(Path(path).read_text())
        data["watchlist"] = [t.upper() for t in data.get("watchlist", [])]
        return cls(**data)

    def targets(self) -> list[tuple[dict, str]]:
        """Expand per-ticker sources into one (source, url) pair per ticker."""
        out = []
        for src in self.sources:
            if not src.get("enabled", True):
                continue
            if src.get("per_ticker"):
                out += [(src, src["url"].replace("{ticker}", t)) for t in self.watchlist]
            else:
                out.append((src, src["url"]))
        return out


class Spider:
    def __init__(self, config: Config, store: Store | None = None, fetcher: Fetcher | None = None):
        self.config = config
        self.store = store or Store(config.database, config.half_life_minutes)
        self.fetcher = fetcher or Fetcher(config.user_agent, min_interval=config.min_host_interval)
        self._cik_map: dict[str, str] | None = None

    def cik_map(self) -> dict[str, str]:
        """SEC CIK -> ticker, fetched once per run."""
        if self._cik_map is None:
            self._cik_map = {}
            resp = self.fetcher.get(SEC_TICKERS_URL)
            if resp:
                for row in json.loads(resp.text).values():
                    self._cik_map[str(row["cik_str"]).zfill(10)] = row["ticker"].upper()
        return self._cik_map

    def _crawl_one(self, src: dict, url: str) -> list[Article]:
        resp = self.fetcher.get(url)
        if not resp:
            return []
        kind = src.get("kind", "rss")
        try:
            articles = PARSERS.get(kind, parse_feed)(src["name"], resp.text)
        except Exception:  # one broken feed must not stop the crawl
            log.exception("could not parse %s", url)
            return []
        if kind == "sec":
            ciks = self.cik_map()
            for art in articles:
                if (m := _SEC_TITLE.match(art.title)) and (sym := ciks.get(m.group(2))):
                    art.summary = f"${sym} {art.summary}"
        return articles

    def relevant(self, art: Article) -> bool:
        """Day-trading filter: a named stock plus a catalyst the trading plan acts on (or vetoes on)."""
        rules = self.config.filter
        if not rules.get("enabled", True):
            return True
        if rules.get("require_ticker", True) and not art.tickers:
            return False
        from .strategy import Plan

        plan = Plan.from_config(self.config.bot)
        wanted = plan.bullish | plan.avoid | set(rules.get("extra_catalysts", []))
        if rules.get("keep_macro", False):
            wanted.add("macro")
        return bool(wanted.intersection(art.catalysts))

    def crawl(self, now: datetime | None = None) -> list[Article]:
        """Fetches all sources and returns only stories not seen before, best first."""
        now = now or datetime.now(timezone.utc)
        cutoff = now - timedelta(hours=self.config.max_age_hours)
        watch = set(self.config.watchlist)
        # Fetcher throttles per host, so threads only overlap requests to different sites.
        with ThreadPoolExecutor(max_workers=8) as pool:
            batches = pool.map(lambda t: self._crawl_one(*t), self.config.targets())
        fresh, dropped = [], 0
        for batch in batches:
            for art in batch:
                if art.published < cutoff:
                    continue
                enrich(art, watch, self.config.aliases, now, self.config.half_life_minutes)
                if not self.relevant(art):
                    dropped += 1
                    continue
                if self.store.add(art):
                    fresh.append(art)
        fresh.sort(key=lambda a: a.score, reverse=True)
        log.info("crawl done: %d new stories, %d ignored as not tradeable news", len(fresh), dropped)
        return fresh
