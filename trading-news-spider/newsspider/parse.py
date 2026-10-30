"""Turn raw feed payloads into Articles."""

from __future__ import annotations

import calendar
import html
import json
import re
from datetime import datetime, timezone

import feedparser

from .models import Article

_TAG = re.compile(r"<[^>]+>")


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(_TAG.sub(" ", text or ""))).strip()


def _entry_time(entry) -> datetime:
    for key in ("published_parsed", "updated_parsed"):
        if parsed := entry.get(key):
            return datetime.fromtimestamp(calendar.timegm(parsed), tz=timezone.utc)
    return datetime.now(timezone.utc)


def parse_feed(source: str, payload: str) -> list[Article]:
    feed = feedparser.parse(payload)
    articles = []
    for entry in feed.entries:
        title, link = clean(entry.get("title", "")), entry.get("link", "")
        if not title or not link:
            continue
        articles.append(
            Article(
                source=source,
                title=title,
                url=link,
                published=_entry_time(entry),
                summary=clean(entry.get("summary", ""))[:1000],
            )
        )
    return articles


def parse_reddit(source: str, payload: str) -> list[Article]:
    data = json.loads(payload)
    articles = []
    for child in data.get("data", {}).get("children", []):
        post = child.get("data", {})
        if post.get("stickied") or not post.get("title"):
            continue
        articles.append(
            Article(
                source=source,
                title=clean(post["title"]),
                url="https://www.reddit.com" + post.get("permalink", ""),
                published=datetime.fromtimestamp(post.get("created_utc", 0), tz=timezone.utc),
                summary=clean(post.get("selftext", ""))[:1000],
            )
        )
    return articles


PARSERS = {"rss": parse_feed, "reddit": parse_reddit}
