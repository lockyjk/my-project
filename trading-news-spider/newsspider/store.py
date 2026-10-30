"""SQLite storage with URL and syndicated-title de-duplication."""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta, timezone

from .models import Article

SCHEMA = """
CREATE TABLE IF NOT EXISTS articles (
    uid         TEXT PRIMARY KEY,
    title_key   TEXT NOT NULL,
    source      TEXT NOT NULL,
    sources     TEXT NOT NULL,   -- JSON list of every source that ran the story
    title       TEXT NOT NULL,
    url         TEXT NOT NULL,
    published   TEXT NOT NULL,
    first_seen  TEXT NOT NULL,
    summary     TEXT,
    tickers     TEXT NOT NULL,
    catalysts   TEXT NOT NULL,
    sentiment   REAL NOT NULL,
    score       REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_title_key ON articles(title_key);
CREATE INDEX IF NOT EXISTS idx_published ON articles(published);
"""

# Each extra outlet carrying the same story makes it more credible.
CORROBORATION_BOOST = 0.25


class Store:
    def __init__(self, path: str, half_life_min: float = 60):
        self.half_life_min = half_life_min
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)

    def add(self, article: Article) -> bool:
        """Returns True when the article is a new story."""
        if self.db.execute("SELECT 1 FROM articles WHERE uid = ?", (article.uid,)).fetchone():
            return False
        cutoff = (article.published - timedelta(hours=48)).isoformat()
        dupe = self.db.execute(
            "SELECT uid, sources, score FROM articles WHERE title_key = ? AND published >= ?",
            (article.title_key, cutoff),
        ).fetchone()
        if dupe:
            sources = json.loads(dupe["sources"])
            if article.source not in sources:
                sources.append(article.source)
                self.db.execute(
                    "UPDATE articles SET sources = ?, score = ? WHERE uid = ?",
                    (json.dumps(sources), round(dupe["score"] * (1 + CORROBORATION_BOOST), 3), dupe["uid"]),
                )
                self.db.commit()
            return False
        self.db.execute(
            "INSERT INTO articles VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                article.uid, article.title_key, article.source, json.dumps([article.source]),
                article.title, article.url, article.published.isoformat(),
                datetime.now(timezone.utc).isoformat(), article.summary,
                json.dumps(article.tickers), json.dumps(article.catalysts),
                article.sentiment, article.score,
            ),
        )
        self.db.commit()
        return True

    def recent(self, since: timedelta, ticker: str | None = None, limit: int = 50) -> list[dict]:
        """Stories published within `since`, ranked by score decayed to the current time."""
        now = datetime.now(timezone.utc)
        rows = self.db.execute(
            "SELECT * FROM articles WHERE published >= ?", ((now - since).isoformat(),)
        ).fetchall()
        out = []
        for row in rows:
            item = dict(row)
            for key in ("sources", "tickers", "catalysts"):
                item[key] = json.loads(item[key])
            if ticker and ticker.upper() not in item["tickers"]:
                continue
            # Stored scores are decayed to crawl time; keep decaying since then.
            minutes = max(0.0, (now - datetime.fromisoformat(item["first_seen"])).total_seconds() / 60)
            item["score"] = round(item["score"] * 0.5 ** (minutes / self.half_life_min), 3)
            out.append(item)
        out.sort(key=lambda i: (i["score"], i["published"]), reverse=True)
        return out[:limit]

    def ticker_heat(self, since: timedelta, limit: int = 20) -> list[dict]:
        """Tickers ranked by how much high-impact news they have had lately."""
        heat: dict[str, dict] = {}
        for item in self.recent(since, limit=10_000):
            for sym in item["tickers"]:
                h = heat.setdefault(sym, {"ticker": sym, "stories": 0, "score": 0.0, "sentiment": 0.0, "catalysts": set()})
                h["stories"] += 1
                h["score"] += item["score"]
                h["sentiment"] += item["sentiment"]
                h["catalysts"].update(item["catalysts"])
        ranked = sorted(heat.values(), key=lambda h: h["score"], reverse=True)[:limit]
        for h in ranked:
            h["score"] = round(h["score"], 2)
            h["sentiment"] = round(h["sentiment"] / h["stories"], 2)
            h["catalysts"] = sorted(h["catalysts"])
        return ranked
