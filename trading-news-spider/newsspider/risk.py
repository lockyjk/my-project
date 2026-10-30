"""Position sizing and the circuit breakers that keep one bad day from becoming a bad month."""

from __future__ import annotations

from dataclasses import dataclass, fields


@dataclass
class RiskRules:
    risk_per_trade_pct: float = 0.5    # equity lost if the stop is hit
    max_position_pct: float = 25.0     # cap on any single position's size
    max_open_positions: int = 3
    daily_loss_limit_pct: float = 1.5  # stop trading for the day after losing this much
    max_trades_per_day: int = 6

    @classmethod
    def from_config(cls, data: dict) -> RiskRules:
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in known})

    def size(self, equity: float, entry: float, stop: float) -> int:
        per_share = entry - stop
        if per_share <= 0 or entry <= 0:
            return 0
        by_risk = equity * self.risk_per_trade_pct / 100 / per_share
        by_cap = equity * self.max_position_pct / 100 / entry
        return int(min(by_risk, by_cap))

    def can_open(self, ticker: str, open_tickers: set[str], traded_today: set[str], day_pnl: float, equity: float) -> tuple[bool, str]:
        if day_pnl <= -equity * self.daily_loss_limit_pct / 100:
            return False, "daily loss limit hit, done for today"
        if ticker in open_tickers or ticker in traded_today:
            return False, "already traded this ticker today"
        if len(open_tickers) >= self.max_open_positions:
            return False, "max open positions"
        if len(traded_today) >= self.max_trades_per_day:
            return False, "max trades for today"
        return True, "ok"
