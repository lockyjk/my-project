"""Minute bars (Yahoo's public chart endpoint) and the indicators the trading plan uses."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, time, timezone
from zoneinfo import ZoneInfo

from .fetch import Fetcher

ET = ZoneInfo("America/New_York")
OPEN, CLOSE = time(9, 30), time(16, 0)
BARS_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?interval=1m&includePrePost=false&{span}"


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


def fetch_bars(fetcher: Fetcher, ticker: str, start: datetime | None = None, end: datetime | None = None) -> list[Bar]:
    """Last 5 sessions by default. Yahoo serves 1-minute bars for about the last 30 days, 7 days per request."""
    span = f"period1={int(start.timestamp())}&period2={int(end.timestamp())}" if start and end else "range=5d"
    resp = fetcher.get(BARS_URL.format(ticker=ticker, span=span))
    return parse_bars(resp.text) if resp else []


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
