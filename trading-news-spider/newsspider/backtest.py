"""Replay the plan over news the spider collected and the minute bars that followed it.

Fills are deliberately pessimistic: entry at the next bar's open plus slippage, a stop that is gapped
through fills at the open, and when one bar touches both stop and target the stop is assumed first.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta
from typing import Callable

from .bars import Bar
from .risk import RiskRules
from .strategy import Plan, Signal, _t, check_entry, qualifying_news


@dataclass
class Trade:
    ticker: str
    day: date
    entry_time: datetime
    entry: float
    stop: float
    exit_time: datetime
    exit: float
    exit_reason: str
    r: float
    signal_reason: str
    news: str
    qty: int = 0
    pnl: float = 0.0
    catalysts: list[str] = field(default_factory=list)
    meta: dict = field(default_factory=dict)


def simulate_trade(plan, signal: Signal, after: list[Bar], news: str = "", time_exit: Callable[[Bar], bool] | None = None) -> Trade | None:
    """Play out a signal over the bars that follow it. `time_exit(bar)` says when to sell at that bar's open.

    Exits, checked in this order on every bar (worst case first):
      time exit -> stop -> scale-out at `scale_out_r` -> fixed target (only when not trailing).
    Then for the next bar: stop to breakeven at `breakeven_r`, and with `trail_bars` the stop trails
    under the lowest low of the last N bars once the trade is at breakeven.
    """
    if not after:
        return None
    if time_exit is None:
        exit_at = _t(plan.exit_time)
        time_exit = lambda bar: bar.t.time() >= exit_at  # noqa: E731
    slip = plan.slippage_pct / 100
    entry = after[0].o * (1 + slip)
    risk = entry - signal.stop
    if risk <= 0:
        return None
    trailing = getattr(plan, "trail_bars", 0) > 0
    scale_r, scale_part = getattr(plan, "scale_out_r", 0.0), getattr(plan, "scale_out_pct", 50.0) / 100
    stop, at_breakeven, scaled = signal.stop, False, False
    target = math.inf if trailing else entry + plan.target_r * risk
    left, banked_r = 1.0, 0.0  # share of the position still held; R already locked in by partial sales

    def r_of(price: float) -> float:
        return (price * (1 - slip) - entry) / risk

    for i, bar in enumerate(after):
        if time_exit(bar):
            price, why, when = bar.o, "time exit", bar.t
            break
        if bar.l <= stop:
            price, when = min(stop, bar.o), bar.t
            why = "trailing stop" if trailing and stop > entry else "breakeven stop" if at_breakeven else "stop"
            break
        if scale_r and not scaled and bar.h >= entry + scale_r * risk:
            banked_r += scale_part * r_of(max(entry + scale_r * risk, bar.o))
            left, scaled = left - scale_part, True
            stop, at_breakeven = max(stop, entry), True
        if bar.h >= target:
            price, why, when = max(target, bar.o), "target", bar.t
            break
        if not at_breakeven and bar.h >= entry + plan.breakeven_r * risk:
            stop, at_breakeven = entry, True
        if trailing and at_breakeven:
            stop = max(stop, min(b.l for b in after[max(0, i - plan.trail_bars + 1) : i + 1]))
    else:
        price, why, when = after[-1].c, "end of data", after[-1].t
    r = banked_r + left * r_of(price)
    if scaled:
        why += " (after scale-out)"
    return Trade(signal.ticker, after[0].t.date(), after[0].t, round(entry, 4), round(signal.stop, 4), when,
                 round(entry + r * risk, 4), why, round(r, 3), signal.reason, news, meta=dict(signal.meta))


def market_for(sessions: dict[date, list[Bar]] | None, day: date) -> tuple[list[Bar], float] | None:
    """The index's bars on `day` and its previous close, or None when not available."""
    if not sessions or day not in sessions:
        return None
    before = [bars for d, bars in sorted(sessions.items()) if d < day]
    return (sessions[day], before[-1][-1].c) if before else None


def find_trade(
    plan: Plan,
    ticker: str,
    sessions: dict[date, list[Bar]],
    day: date,
    news_at: datetime,
    news: str = "",
    market: dict[date, list[Bar]] | None = None,
) -> tuple[Trade | None, str]:
    today = sessions.get(day)
    history = [bars for d, bars in sorted(sessions.items()) if d < day]
    if not today:
        return None, "no bars for that session"
    index = market_for(market, day) if plan.market_filter else None
    reason, market_block = "no entry signal", ""
    for i in range(1, len(today)):
        if today[i - 1].t.time() >= _t(plan.entry_end):
            break
        signal, reason = check_entry(plan, ticker, today[:i], history, news_at, index)
        if signal:
            return simulate_trade(plan, signal, today[i:], news), signal.reason
        if reason.startswith("market"):
            market_block = market_block or reason  # report the setup the market filter stopped
        if reason.startswith(("gap", "illiquid", "price")):
            break  # these will not change later in the day
    return None, market_block or reason


@dataclass
class Report:
    trades: list[Trade]
    skipped: list[tuple[str, str, str]]  # ticker, day, why
    start_equity: float
    end_equity: float
    max_drawdown_pct: float

    @property
    def stats(self) -> dict:
        rs = [t.r for t in self.trades]
        wins, losses = [r for r in rs if r > 0], [r for r in rs if r <= 0]
        gross_win = sum(t.pnl for t in self.trades if t.pnl > 0)
        gross_loss = -sum(t.pnl for t in self.trades if t.pnl < 0)
        return {
            "trades": len(rs),
            "win_rate_pct": round(len(wins) / len(rs) * 100, 1) if rs else 0.0,
            "avg_win_r": round(sum(wins) / len(wins), 2) if wins else 0.0,
            "avg_loss_r": round(sum(losses) / len(losses), 2) if losses else 0.0,
            "expectancy_r": round(sum(rs) / len(rs), 3) if rs else 0.0,
            "profit_factor": round(gross_win / gross_loss, 2) if gross_loss else (math.inf if gross_win else 0.0),
            "return_pct": round((self.end_equity / self.start_equity - 1) * 100, 2),
            "max_drawdown_pct": round(self.max_drawdown_pct, 2),
        }

    def to_dict(self) -> dict:
        return {
            "stats": self.stats,
            "trades": [{**asdict(t), "day": t.day.isoformat(), "entry_time": t.entry_time.isoformat(), "exit_time": t.exit_time.isoformat()} for t in self.trades],
            "skipped": self.skipped,
        }


def run_backtest(
    plan: Plan,
    rules: RiskRules,
    articles: list[dict],
    load_sessions: Callable[[str, date], dict[date, list[Bar]]],
    equity: float = 100_000,
) -> Report:
    """`load_sessions(ticker, day)` returns that day's bars plus a few prior sessions."""
    raw, skipped = [], []
    for (ticker, day), art in sorted(qualifying_news(articles, plan).items(), key=lambda kv: (kv[0][1], kv[0][0])):
        market = load_sessions(plan.market_ticker, day) if plan.market_filter else None
        trade, why = find_trade(plan, ticker, load_sessions(ticker, day), day, art["published_at"], art["title"], market)
        if trade:
            trade.catalysts = sorted(set(art["catalysts"]) & plan.bullish)
            raw.append(trade)
        else:
            skipped.append((ticker, day.isoformat(), why))

    return apply_risk(raw, skipped, rules, equity)


def apply_risk(raw: list[Trade], skipped: list, rules: RiskRules, equity: float) -> Report:
    """Apply the account's risk rules in time order, compounding equity day by day."""
    start, peak, max_dd = equity, equity, 0.0
    taken: list[Trade] = []
    for day in sorted({t.day for t in raw}):
        day_trades = sorted((t for t in raw if t.day == day), key=lambda t: t.entry_time)
        open_trades: list[Trade] = []
        traded: set[str] = set()
        day_pnl, day_equity = 0.0, equity
        for t in day_trades:
            open_trades = [o for o in open_trades if o.exit_time > t.entry_time]
            closed_pnl = sum(o.pnl for o in taken if o.day == day and o.exit_time <= t.entry_time)
            ok, why = rules.can_open(t.ticker, {o.ticker for o in open_trades}, traded, closed_pnl, day_equity)
            qty = rules.size(day_equity, t.entry, t.stop) if ok else 0
            if not qty:
                skipped.append((t.ticker, day.isoformat(), why if not ok else "position too small"))
                continue
            t.qty, t.pnl = qty, round(qty * (t.exit - t.entry), 2)
            taken.append(t)
            open_trades.append(t)
            traded.add(t.ticker)
            day_pnl += t.pnl
        equity += day_pnl
        peak = max(peak, equity)
        max_dd = max(max_dd, (peak - equity) / peak * 100)
    return Report(taken, skipped, start, equity, max_dd)


def passes_live_gate(stats: dict, min_trades: int = 30, min_profit_factor: float = 1.2) -> tuple[bool, str]:
    if stats["trades"] < min_trades:
        return False, f"only {stats['trades']} backtest trades; need {min_trades}+ to judge the plan"
    if stats["expectancy_r"] <= 0:
        return False, f"backtest expectancy {stats['expectancy_r']}R is not positive"
    if stats["profit_factor"] < min_profit_factor:
        return False, f"profit factor {stats['profit_factor']} below {min_profit_factor}"
    return True, "backtest meets the live-trading bar"


def default_loader(fetcher, archive=None) -> Callable[[str, date], dict[date, list[Bar]]]:
    """Regular-hours sessions around `day`, from the bar archive when it has them. Memoized, so a
    tuning run that replays the same news many times only downloads each ticker-day once."""
    from functools import lru_cache

    from .bars import ET, by_session, fetch_bars

    @lru_cache(maxsize=4096)
    def load(ticker: str, day: date) -> dict[date, list[Bar]]:
        start = datetime.combine(day - timedelta(days=7), datetime.min.time(), ET)
        end = datetime.combine(day + timedelta(days=1), datetime.min.time(), ET)
        bars = archive.range(ticker, start, end) if archive else fetch_bars(fetcher, ticker, start, end)
        return by_session(bars)

    return load


def breakdown(trades: list[Trade]) -> dict[str, dict[str, dict]]:
    """Expectancy split by catalyst, entry hour and move size, to see which kinds of trades pay."""
    groups: dict[str, dict[str, list[float]]] = {"catalyst": {}, "entry hour": {}, "gap / move": {}}
    for t in trades:
        for cat in t.catalysts or ["unknown"]:
            groups["catalyst"].setdefault(cat, []).append(t.r)
        groups["entry hour"].setdefault(f"{t.entry_time.hour:02d}:00", []).append(t.r)
        size = t.meta.get("gap_pct", t.meta.get("move_pct"))
        if size is not None:
            bucket = "under 4%" if size < 4 else "4-8%" if size < 8 else "8%+"
            groups["gap / move"].setdefault(bucket, []).append(t.r)
    return {
        name: {k: {"trades": len(rs), "win_rate_pct": round(sum(r > 0 for r in rs) / len(rs) * 100, 1),
                   "expectancy_r": round(sum(rs) / len(rs), 3)} for k, rs in sorted(g.items())}
        for name, g in groups.items()
    }
