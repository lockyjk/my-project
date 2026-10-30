"""Minute bars (Yahoo's public chart endpoint) and the indicators the trading plan uses."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, time, timezone
from zoneinfo import ZoneInfo

from .fetch import Fetcher

ET = ZoneInfo("America/New_York")
OPEN, CLOSE = time(9, 30), time(16, 0)
BARS_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?interval=1m&includePrePost={extended}&{span}"


@dataclass(frozen=True)
class Bar:
    t: datetime  # bar start, US/Eastern
    o: float
    h: float
    l: float
    c: float
    v: float


def parse_bars(payload: str) -> list[Bar]:
    try:
        result = json.loads(payload)["chart"]["result"][0]
        quote = result["indicators"]["quote"][0]
        stamps = result["timestamp"]
    except (KeyError, IndexError, TypeError, ValueError):
        return []
    bars = []
    for i, ts in enumerate(stamps):
        o, h, l, c, v = (quote[k][i] for k in ("open", "high", "low", "close", "volume"))
        if None in (o, h, l, c):
            continue
        bars.append(Bar(datetime.fromtimestamp(ts, tz=timezone.utc).astimezone(ET), o, h, l, c, v or 0))
    return bars


def fetch_bars(fetcher: Fetcher, ticker: str, start: datetime | None = None, end: datetime | None = None, extended: bool = False) -> list[Bar]:
    """Last 5 sessions by default. Yahoo serves 1-minute bars for about the last 30 days, 7 days per request.
    `extended` adds pre-market (4:00-9:30) and after-hours (16:00-20:00); Yahoo has no overnight bars."""
    span = f"period1={int(start.timestamp())}&period2={int(end.timestamp())}" if start and end else "range=5d"
    resp = fetcher.get(BARS_URL.format(ticker=ticker, span=span, extended=str(extended).lower()))
    return sorted(parse_bars(resp.text), key=lambda b: b.t) if resp else []


def by_session(bars: list[Bar]) -> dict[date, list[Bar]]:
    """Regular-hours bars grouped by trading day, oldest first."""
    days: dict[date, list[Bar]] = {}
    for bar in sorted(bars, key=lambda b: b.t):
        if OPEN <= bar.t.time() < CLOSE:
            days.setdefault(bar.t.date(), []).append(bar)
    return days


def vwap(bars: list[Bar]) -> float:
    volume = sum(b.v for b in bars)
    if not volume:
        return bars[-1].c
    return sum((b.h + b.l + b.c) / 3 * b.v for b in bars) / volume


class BarArchive:
    """Keeps every complete day of minute bars the bot fetches. Yahoo drops 1-minute history after about
    30 days; the archive does not, so backtests can reach as far back as the bot has been running."""

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS bars (ticker TEXT, ext INTEGER, t INTEGER, o REAL, h REAL, l REAL, c REAL, v REAL,
                                     PRIMARY KEY (ticker, ext, t));
    CREATE TABLE IF NOT EXISTS bar_days (ticker TEXT, ext INTEGER, day TEXT, PRIMARY KEY (ticker, ext, day));
    """

    def __init__(self, path: str, fetcher: Fetcher | None):
        import sqlite3

        self.fetcher = fetcher
        self.db = sqlite3.connect(path, timeout=30)
        self.db.executescript(self.SCHEMA)

    def _today(self) -> date:
        return datetime.now(ET).date()

    def _complete_days(self, start: datetime, end: datetime) -> list[date]:
        """Weekdays in the range that are over (bars for them can no longer change)."""
        days, d = [], start.astimezone(ET).date()
        while d <= end.astimezone(ET).date() and d < self._today():
            if d.weekday() < 5:
                days.append(d)
            d = date.fromordinal(d.toordinal() + 1)
        return days

    def _store(self, ticker: str, ext: bool, bars: list[Bar], days: list[date]) -> None:
        if not bars:
            return  # a failed or empty fetch proves nothing about those days
        keep = set(days)
        self.db.executemany(
            "INSERT OR REPLACE INTO bars VALUES (?,?,?,?,?,?,?,?)",
            [(ticker, int(ext), int(b.t.timestamp()), b.o, b.h, b.l, b.c, b.v) for b in bars if b.t.date() in keep],
        )
        self.db.executemany("INSERT OR IGNORE INTO bar_days VALUES (?,?,?)", [(ticker, int(ext), d.isoformat()) for d in days])
        self.db.commit()

    def _read(self, ticker: str, ext: bool, start: datetime, end: datetime) -> list[Bar]:
        rows = self.db.execute(
            "SELECT t,o,h,l,c,v FROM bars WHERE ticker=? AND ext=? AND t>=? AND t<? ORDER BY t",
            (ticker, int(ext), int(start.timestamp()), int(end.timestamp())),
        ).fetchall()
        return [Bar(datetime.fromtimestamp(r[0], tz=timezone.utc).astimezone(ET), *r[1:]) for r in rows]

    def range(self, ticker: str, start: datetime, end: datetime, extended: bool = False) -> list[Bar]:
        days = self._complete_days(start, end)
        have = {r[0] for r in self.db.execute("SELECT day FROM bar_days WHERE ticker=? AND ext=?", (ticker, int(extended)))}
        missing = [d for d in days if d.isoformat() not in have]
        reaches_today = end.astimezone(ET).date() >= self._today()
        fresh: list[Bar] = []
        if (missing or reaches_today) and self.fetcher is not None:
            fresh = fetch_bars(self.fetcher, ticker, start, end, extended)
            self._store(ticker, extended, fresh, missing)
        merged = {b.t: b for b in self._read(ticker, extended, start, end)}
        merged.update({b.t: b for b in fresh})
        return [merged[t] for t in sorted(merged)]

    def recent(self, ticker: str, extended: bool = False) -> list[Bar]:
        """The last 5 sessions, live, archiving every finished day on the way."""
        bars = fetch_bars(self.fetcher, ticker, extended=extended) if self.fetcher else []
        if bars:
            self._store(ticker, extended, bars, sorted({b.t.date() for b in bars if b.t.date() < self._today()}))
        return bars
