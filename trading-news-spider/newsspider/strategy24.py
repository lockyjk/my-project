"""24/5 News Reaction plan: trade the reaction to news in any session, Sunday 20:00 to Friday 20:00 ET.

The regular-hours plan keys off the 9:30 open. Around the clock there is no open, and most catalysts
(earnings at 16:05 or 7:00, FDA decisions, 8-Ks) land outside regular hours, so this plan anchors on
the moment the story came out instead:

  1. News: the same buy and veto catalysts as the Catalyst Momentum plan. A veto story within 12 hours
     either side cancels the trade, and each stock trades at most once per 24 hours.
  2. Reaction: price is 2%+ above the last price before the story, at least 3x the volume usually seen
     at that time of day, and $250k+ has traded since the story (extended hours are thin).
  3. Entry: after the first 15 minutes (the reaction range), a 1-minute bar closes above the reaction
     high and above VWAP measured from the story, no more than 1% above that high, within 2 hours.
  4. Exit: stop under the higher of the reaction low and that VWAP, 2R target, breakeven at +1R,
     sell after 4 hours at most, and always before the Friday 20:00 close for the weekend.
  Costs: 0.15% slippage per side, three times the regular-hours plan, for wider overnight spreads.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field, fields
from datetime import date, datetime, time, timedelta
from typing import Callable

from .bars import ET, Bar
from .backtest import Report, Trade, apply_risk, simulate_trade
from .risk import RiskRules
from .strategy import AVOID, BULLISH, Plan, Signal, _t, news_verdict


@dataclass
class Plan24:
    min_sentiment: float = 0.2
    min_price: float = 5.0
    min_move_pct: float = 2.0
    min_rel_volume: float = 3.0
    min_window_dollar_volume: float = 250_000
    reaction_minutes: int = 15
    entry_window_minutes: int = 120
    max_chase_pct: float = 1.0
    min_stop_pct: float = 0.75
    max_stop_pct: float = 4.0
    target_r: float = 2.0
    breakeven_r: float = 1.0
    max_hold_minutes: int = 240
    weekend_exit: str = "19:55"
    veto_hours: float = 12
    slippage_pct: float = 0.15
    bullish: set[str] = field(default_factory=lambda: set(BULLISH))
    avoid: set[str] = field(default_factory=lambda: set(AVOID))

    @classmethod
    def from_config(cls, data: dict) -> Plan24:
        known = {f.name for f in fields(cls)}
        return cls(**{k: (set(v) if k in ("bullish", "avoid") else v) for k, v in data.items() if k in known})


def session_name(t: datetime) -> str:
    clock = t.astimezone(ET).time()
    if time(4, 0) <= clock < time(9, 30):
        return "pre-market"
    if time(9, 30) <= clock < time(16, 0):
        return "regular"
    if time(16, 0) <= clock < time(20, 0):
        return "after-hours"
    return "overnight"


def is_open_24_5(t: datetime) -> bool:
    """Sunday 20:00 ET through Friday 20:00 ET."""
    t = t.astimezone(ET)
    if t.weekday() == 5:
        return False
    if t.weekday() == 6:
        return t.time() >= time(20, 0)
    if t.weekday() == 4:
        return t.time() < time(20, 0)
    return True


def news_events(articles: list[dict], plan: Plan24) -> list[tuple[str, datetime, dict]]:
    """(ticker, news time, story) for each tradeable story, after vetoes and the once-per-24h rule."""
    as_plan = Plan(min_sentiment=plan.min_sentiment, bullish=plan.bullish, avoid=plan.avoid)
    good, bad = defaultdict(list), defaultdict(list)
    for art in sorted(articles, key=lambda a: a["published"]):
        when = datetime.fromisoformat(art["published"]).astimezone(ET)
        ok, reason = news_verdict(art, as_plan)
        for ticker in art["tickers"]:
            if ok:
                good[ticker].append((when, {**art, "reason": reason}))
            elif set(art["catalysts"]) & plan.avoid:
                bad[ticker].append(when)
    events = []
    window = timedelta(hours=plan.veto_hours)
    for ticker, stories in good.items():
        last = None
        for when, art in stories:
            if any(abs(when - b) <= window for b in bad[ticker]):
                continue
            if last and when - last < timedelta(hours=24):
                continue
            if not is_open_24_5(when):
                when = _next_open(when)
            events.append((ticker, when, art))
            last = when
    return sorted(events, key=lambda e: e[1])


def _next_open(t: datetime) -> datetime:
    """Weekend news is first tradeable at the Sunday 20:00 open."""
    t = t.astimezone(ET)
    days = (6 - t.weekday()) % 7
    sunday = (t + timedelta(days=days)).replace(hour=20, minute=0, second=0, microsecond=0)
    return sunday if sunday > t else sunday + timedelta(days=7)


def check_entry_24(plan: Plan24, ticker: str, bars: list[Bar], news_at: datetime) -> tuple[Signal | None, str]:
    """Decide on the latest bar of `bars` (everything known so far, oldest first)."""
    if not bars:
        return None, "no price data"
    bar = bars[-1]
    now = bar.t + timedelta(minutes=1)
    if now <= news_at:
        return None, "news not out yet"
    if now - news_at > timedelta(minutes=plan.entry_window_minutes):
        return None, "entry window over"
    before = [b for b in bars if b.t + timedelta(minutes=1) <= news_at]
    after = [b for b in bars if b.t + timedelta(minutes=1) > news_at]
    if not before:
        return None, "no price before the news"
    reaction = [b for b in after if b.t < after[0].t + timedelta(minutes=plan.reaction_minutes)]
    if len(reaction) == len(after):
        return None, "reaction range not complete"

    ref = before[-1].c
    move = (bar.c / ref - 1) * 100
    if bar.c < plan.min_price:
        return None, f"price ${bar.c:.2f} under ${plan.min_price}"
    if move < plan.min_move_pct:
        return None, f"move {move:+.1f}% since the news, below {plan.min_move_pct}%"
    traded_value = sum(b.v * b.c for b in after)
    if traded_value < plan.min_window_dollar_volume:
        return None, f"too thin: ${traded_value / 1e3:.0f}k traded since the news"
    volume = sum(b.v for b in after)
    usual_days = []
    for k in range(1, 8):
        lo, hi = after[0].t - timedelta(days=k), now - timedelta(days=k)
        if lo.weekday() >= 5:
            continue
        usual_days.append(sum(b.v for b in before if lo <= b.t < hi))
        if len(usual_days) == 5:
            break
    usual = sum(usual_days) / len(usual_days) if usual_days else 0
    rel_volume = volume / max(usual, 1)
    if rel_volume < plan.min_rel_volume:
        return None, f"relative volume {rel_volume:.1f}x below {plan.min_rel_volume}x"

    high, low = max(b.h for b in reaction), min(b.l for b in reaction)
    level = sum((b.h + b.l + b.c) / 3 * b.v for b in after) / volume if volume else bar.c
    if bar.c <= high or bar.c <= level:
        return None, "no breakout above reaction range and VWAP"
    if (bar.c / high - 1) * 100 > plan.max_chase_pct:
        return None, "too extended above the reaction range"
    entry, stop = bar.c, max(low, level) * 0.999
    risk_pct = (entry - stop) / entry * 100
    if risk_pct > plan.max_stop_pct:
        return None, f"stop {risk_pct:.1f}% away is too wide"
    if risk_pct < plan.min_stop_pct:
        stop = entry * (1 - plan.min_stop_pct / 100)
    reason = (f"{session_name(bar.t)}: {move:+.1f}% since news, {rel_volume:.1f}x volume, "
              f"broke reaction range {high:.2f} above VWAP {level:.2f}")
    return Signal(ticker, now, round(entry, 4), round(stop, 4), round(entry + plan.target_r * (entry - stop), 4), reason), reason


def time_exit_24(plan: Plan24, entered: datetime) -> Callable[[Bar], bool]:
    friday_close = _t(plan.weekend_exit)

    def should_exit(bar: Bar) -> bool:
        if bar.t - entered >= timedelta(minutes=plan.max_hold_minutes):
            return True
        if bar.t.weekday() == 4 and bar.t.time() >= friday_close:
            return True
        return bar.t.weekday() >= 5  # data resumed after a weekend we should not have held through

    return should_exit


def find_trade_24(plan: Plan24, ticker: str, bars: list[Bar], news_at: datetime, news: str = "") -> tuple[Trade | None, str]:
    reason = "no entry signal"
    start = next((i for i, b in enumerate(bars) if b.t + timedelta(minutes=1) > news_at), None)
    if start is None:
        return None, "no price data after the news"
    for i in range(start + 1, len(bars)):
        signal, reason = check_entry_24(plan, ticker, bars[:i], news_at)
        if signal:
            trade = simulate_trade(plan, signal, bars[i:], news, time_exit_24(plan, bars[i].t))
            return trade, signal.reason
        if reason.startswith(("entry window over", "price", "no price before")):
            break
    return None, reason


def run_backtest_24(
    plan: Plan24,
    rules: RiskRules,
    articles: list[dict],
    load_bars: Callable[[str, datetime], list[Bar]],
    equity: float = 100_000,
) -> Report:
    """`load_bars(ticker, news_at)` returns extended-hours bars from about a week before the story to a day after."""
    raw, skipped = [], []
    for ticker, when, art in news_events(articles, plan):
        trade, why = find_trade_24(plan, ticker, load_bars(ticker, when), when, art["title"])
        if trade:
            raw.append(trade)
        else:
            skipped.append((ticker, when.isoformat(timespec="minutes"), why))
    return apply_risk(raw, skipped, rules, equity)


def by_session_stats(trades: list[Trade]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for t in trades:
        s = out.setdefault(session_name(t.entry_time), {"trades": 0, "wins": 0, "total_r": 0.0, "pnl": 0.0})
        s["trades"] += 1
        s["wins"] += t.r > 0
        s["total_r"] = round(s["total_r"] + t.r, 3)
        s["pnl"] = round(s["pnl"] + t.pnl, 2)
    return out


def default_loader_24(fetcher) -> Callable[[str, datetime], list[Bar]]:
    from .bars import fetch_bars

    def load(ticker: str, news_at: datetime) -> list[Bar]:
        return fetch_bars(fetcher, ticker, news_at - timedelta(days=7), news_at + timedelta(days=1), extended=True)

    return load
