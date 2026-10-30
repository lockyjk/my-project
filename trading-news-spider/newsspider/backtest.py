"""Replay the plan over news the spider collected and the minute bars that followed it.

Fills are deliberately pessimistic: entry at the next bar's open plus slippage, a stop that is gapped
through fills at the open, and when one bar touches both stop and target the stop is assumed first.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass
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


def simulate_trade(plan: Plan, signal: Signal, after: list[Bar], news: str = "") -> Trade | None:
    """Play out a signal over the bars that follow it."""
    if not after:
        return None
    entry = after[0].o * (1 + plan.slippage_pct / 100)
    risk = entry - signal.stop
    if risk <= 0:
        return None
    stop, target, at_breakeven = signal.stop, entry + plan.target_r * risk, False
    exit_at = _t(plan.exit_time)
    for bar in after:
        if bar.t.time() >= exit_at:
            price, why, when = bar.o, "time exit", bar.t
            break
        if bar.l <= stop:
            price, why, when = min(stop, bar.o), "breakeven stop" if at_breakeven else "stop", bar.t
            break
        if bar.h >= target:
            price, why, when = max(target, bar.o), "target", bar.t
            break
        if not at_breakeven and bar.h >= entry + plan.breakeven_r * risk:
            stop, at_breakeven = entry, True
    else:
        price, why, when = after[-1].c, "end of data", after[-1].t
    price *= 1 - plan.slippage_pct / 100
    return Trade(signal.ticker, after[0].t.date(), after[0].t, round(entry, 4), round(signal.stop, 4), when,
                 round(price, 4), why, round((price - entry) / risk, 3), signal.reason, news)


def find_trade(plan: Plan, ticker: str, sessions: dict[date, list[Bar]], day: date, news_at: datetime, news: str = "") -> tuple[Trade | None, str]:
    today = sessions.get(day)
    history = [bars for d, bars in sorted(sessions.items()) if d < day]
    if not today:
        return None, "no bars for that session"
    reason = "no entry signal"
    for i in range(1, len(today)):
        if today[i - 1].t.time() >= _t(plan.entry_end):
            break
        signal, reason = check_entry(plan, ticker, today[:i], history, news_at)
        if signal:
            return simulate_trade(plan, signal, today[i:], news), signal.reason
        if reason.startswith(("gap", "illiquid", "price")):
            break  # these will not change later in the day
    return None, reason


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
        trade, why = find_trade(plan, ticker, load_sessions(ticker, day), day, art["published_at"], art["title"])
        if trade:
            raw.append(trade)
        else:
            skipped.append((ticker, day.isoformat(), why))

    # Apply the account's risk rules in time order, compounding equity day by day.
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


def default_loader(fetcher) -> Callable[[str, date], dict[date, list[Bar]]]:
    from .bars import ET, by_session, fetch_bars

    def load(ticker: str, day: date) -> dict[date, list[Bar]]:
        start = datetime.combine(day - timedelta(days=7), datetime.min.time(), ET)
        end = datetime.combine(day + timedelta(days=1), datetime.min.time(), ET)
        return by_session(fetch_bars(fetcher, ticker, start, end))

    return load
