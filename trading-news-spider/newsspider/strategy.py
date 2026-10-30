"""The Catalyst Momentum plan: trade stocks the spider finds good news on, only when price confirms.

Rules (long only, flat by the close):
  1. News: since the last close, the stock had a story with positive sentiment and a catalyst that
     tends to keep moving price (earnings, guidance, FDA, contract, upgrade, buyback). Skip anything
     with dilution, bankruptcy, short-seller, legal or halt news, and merger targets (they pin to the
     deal price instead of trending).
  2. In play: gapped up at least 2% on the open, trading at least 2x its normal volume for the time of
     day, price of $5 or more, and $20M+ average daily dollar volume, so fills are realistic.
  3. Entry: after the first 15 minutes, a 1-minute bar closes above the opening-range high and above
     VWAP, no more than 1% above the range high (no chasing). Entries only until 11:30 ET.
  4. Exit: stop under the higher of the opening-range low and VWAP. Take profit at 2R. Move the stop
     to breakeven at +1R. Anything still open is sold at 15:55 ET.
"""

from __future__ import annotations

from dataclasses import dataclass, field, fields
from datetime import date, datetime, time, timedelta

from .bars import ET, Bar, vwap

BULLISH = {"earnings", "guidance", "fda", "contract", "analyst", "buyback"}
AVOID = {"offering", "bankruptcy", "short_report", "legal", "halt", "merger"}


def _t(text: str) -> time:
    h, m = text.split(":")
    return time(int(h), int(m))


@dataclass
class Plan:
    min_sentiment: float = 0.2
    min_price: float = 5.0
    min_dollar_volume: float = 20e6
    min_gap_pct: float = 2.0
    min_rel_volume: float = 2.0
    opening_range_minutes: int = 15
    max_chase_pct: float = 1.0
    entry_start: str = "09:45"
    entry_end: str = "11:30"
    exit_time: str = "15:55"
    min_stop_pct: float = 0.5
    max_stop_pct: float = 3.0
    target_r: float = 2.0
    breakeven_r: float = 1.0
    slippage_pct: float = 0.05
    bullish: set[str] = field(default_factory=lambda: set(BULLISH))
    avoid: set[str] = field(default_factory=lambda: set(AVOID))

    @classmethod
    def from_config(cls, data: dict) -> Plan:
        known = {f.name for f in fields(cls)}
        kwargs = {k: (set(v) if k in ("bullish", "avoid") else v) for k, v in data.items() if k in known}
        return cls(**kwargs)


@dataclass
class Signal:
    ticker: str
    time: datetime
    entry: float
    stop: float
    target: float
    reason: str


# --- news ------------------------------------------------------------------


def news_verdict(article: dict, plan: Plan) -> tuple[bool, str]:
    cats = set(article["catalysts"])
    if bad := cats & plan.avoid:
        return False, f"avoid catalyst: {', '.join(sorted(bad))}"
    if not cats & plan.bullish:
        return False, "no bullish catalyst"
    if article["sentiment"] < plan.min_sentiment:
        return False, f"sentiment {article['sentiment']:+.2f} too weak"
    return True, f"{', '.join(sorted(cats & plan.bullish))} news, sentiment {article['sentiment']:+.2f}"


def session_for(published: datetime) -> date:
    """The trading day a story can first be traded on."""
    local = published.astimezone(ET)
    day = local.date() + (timedelta(days=1) if local.time() >= time(16, 0) else timedelta())
    while day.weekday() >= 5:
        day += timedelta(days=1)
    return day


def qualifying_news(articles: list[dict], plan: Plan) -> dict[tuple[str, date], dict]:
    """(ticker, session) -> earliest qualifying story. Any avoid-story that session vetoes the ticker."""
    found: dict[tuple[str, date], dict] = {}
    vetoed: set[tuple[str, date]] = set()
    for art in sorted(articles, key=lambda a: a["published"]):
        published = datetime.fromisoformat(art["published"])
        ok, reason = news_verdict(art, plan)
        for ticker in art["tickers"]:
            key = (ticker, session_for(published))
            if not ok and set(art["catalysts"]) & plan.avoid:
                vetoed.add(key)
            elif ok and key not in found:
                found[key] = {**art, "reason": reason, "published_at": published}
    return {k: v for k, v in found.items() if k not in vetoed}


# --- price confirmation ----------------------------------------------------


def check_entry(plan: Plan, ticker: str, today: list[Bar], history: list[list[Bar]], news_at: datetime) -> tuple[Signal | None, str]:
    """Decide on the latest bar of `today` (bars so far). `history` holds prior sessions, oldest first."""
    if not today or not history:
        return None, "not enough price history"
    bar = today[-1]
    now = bar.t + timedelta(minutes=1)  # the bar has closed
    if news_at > now:
        return None, "news not out yet"
    if not (_t(plan.entry_start) <= bar.t.time() < _t(plan.entry_end)):
        return None, "outside entry window"
    or_bars = [b for b in today if b.t < today[0].t + timedelta(minutes=plan.opening_range_minutes)]
    if len(or_bars) == len(today):
        return None, "opening range not complete"

    prev_close = history[-1][-1].c
    gap = (today[0].o / prev_close - 1) * 100
    if gap < plan.min_gap_pct:
        return None, f"gap {gap:+.1f}% below {plan.min_gap_pct}%"
    if bar.c < plan.min_price:
        return None, f"price ${bar.c:.2f} under ${plan.min_price}"
    dollar_volume = sum(sum(b.v for b in day) * day[-1].c for day in history) / len(history)
    if dollar_volume < plan.min_dollar_volume:
        return None, f"illiquid: ${dollar_volume / 1e6:.1f}M/day"
    n = len(today)
    usual = sum(sum(b.v for b in day[:n]) for day in history) / len(history)
    rel_volume = sum(b.v for b in today) / usual if usual else 0
    if rel_volume < plan.min_rel_volume:
        return None, f"relative volume {rel_volume:.1f}x below {plan.min_rel_volume}x"

    or_high, or_low = max(b.h for b in or_bars), min(b.l for b in or_bars)
    level = vwap(today)
    if bar.c <= or_high or bar.c <= level:
        return None, "no breakout above opening range and VWAP"
    if (bar.c / or_high - 1) * 100 > plan.max_chase_pct:
        return None, "too extended above the opening range"

    entry = bar.c
    stop = max(or_low, level) * 0.999
    risk_pct = (entry - stop) / entry * 100
    if risk_pct > plan.max_stop_pct:
        return None, f"stop {risk_pct:.1f}% away is too wide"
    if risk_pct < plan.min_stop_pct:
        stop = entry * (1 - plan.min_stop_pct / 100)
    target = entry + plan.target_r * (entry - stop)
    reason = f"gap {gap:+.1f}%, {rel_volume:.1f}x volume, broke opening range {or_high:.2f} above VWAP {level:.2f}"
    return Signal(ticker, now, round(entry, 4), round(stop, 4), round(target, 4), reason), reason
