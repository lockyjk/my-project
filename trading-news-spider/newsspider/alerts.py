"""Terminal and webhook output."""

from __future__ import annotations

import logging
import sys
from datetime import datetime, timezone

import requests

from .models import Article

log = logging.getLogger(__name__)

_COLOR = sys.stdout.isatty()


def _paint(text: str, code: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


def arrow(sentiment: float) -> str:
    if sentiment > 0.15:
        return _paint("▲", "32")
    if sentiment < -0.15:
        return _paint("▼", "31")
    return "•"


def age(published: datetime | str) -> str:
    if isinstance(published, str):
        published = datetime.fromisoformat(published)
    minutes = int((datetime.now(timezone.utc) - published).total_seconds() // 60)
    return f"{minutes}m" if minutes < 120 else f"{minutes // 60}h"


def format_line(item: Article | dict) -> str:
    get = item.get if isinstance(item, dict) else lambda k: getattr(item, k)
    tickers = " ".join(f"${t}" for t in get("tickers")[:4]) or "—"
    tags = ",".join(get("catalysts")) or "news"
    return (
        f"{arrow(get('sentiment'))} {get('score'):>6.2f}  {age(get('published')):>4}  "
        f"{_paint(tickers, '1'):<20} [{tags}] {get('title')}  ({get('source')})\n"
        f"           {get('url')}"
    )


def send_webhook(url: str, article: Article) -> None:
    tickers = " ".join(f"${t}" for t in article.tickers) or "market"
    text = f"**{tickers}** [{', '.join(article.catalysts) or 'news'}] {article.title}\n{article.url}"
    try:
        # "content" is Discord's field, "text" is Slack's; each ignores the other.
        requests.post(url, json={"content": text, "text": text}, timeout=10)
    except requests.RequestException as exc:
        log.warning("webhook failed: %s", exc)


def alert(articles: list[Article], min_score: float, webhook_url: str = "") -> list[Article]:
    hot = [a for a in articles if a.score >= min_score]
    for art in hot:
        print(_paint("ALERT ", "1;33") + format_line(art), flush=True)
        if webhook_url:
            send_webhook(webhook_url, art)
    return hot
