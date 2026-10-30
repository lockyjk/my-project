"""Paper-trade the 24/5 News Reaction plan: runs whenever the 24/5 market is open."""

from __future__ import annotations

from dataclasses import asdict
from datetime import datetime, timedelta

from .bars import ET, Bar
from .strategy24 import Plan24, check_entry_24, is_open_24_5, must_exit_24, news_events
from .trader import Trader

STALE = timedelta(minutes=3)


class Trader24(Trader):
    plan: Plan24

    def tick(self, now: datetime) -> None:
        now = now.astimezone(ET)
        if not is_open_24_5(now):
            return
        prices = self._manage_open(now)
        self._look_for_entries(now, now.date().isoformat(), prices)

    def _known(self, ticker: str, now: datetime) -> list[Bar]:
        return [b for b in self.bars(ticker) if b.t + timedelta(minutes=1) <= now]

    def _manage_open(self, now: datetime) -> dict[str, float]:
        prices = {}
        for ticker in list(self.broker.positions):
            bars = self._known(ticker, now)
            lvl = self.book.get(ticker)
            if not bars or not lvl:
                continue
            last = bars[-1]
            prices[ticker] = last.c
            if must_exit_24(self.plan, datetime.fromisoformat(lvl["time"]), now):
                pnl = self.broker.sell(ticker, last.c, "time exit", at=now)
                self.log("exit", now, ticker=ticker, price=last.c, reason="time exit", pnl=round(pnl, 2))
                self.book.pop(ticker, None)
            else:
                self._check_levels(ticker, last, lvl, now)
        return prices

    def _look_for_entries(self, now: datetime, day: str, prices: dict[str, float]) -> None:
        window = timedelta(minutes=self.plan.entry_window_minutes)
        live = [(t, when, art) for t, when, art in news_events(self.news(), self.plan) if when <= now < when + window]
        if not live:
            return
        equity = self.broker.equity(prices)
        traded = self.traded.setdefault(day, set()) | self.broker.traded_today(day)
        for ticker, when, art in live:
            ok, why = self.rules.can_open(ticker, set(self.broker.positions), traded, self.broker.day_pnl(day), equity)
            if not ok:
                self._skip(now, ticker, why)
                if "daily loss" in why:
                    return
                continue
            bars = self._known(ticker, now)
            if not bars or now - (bars[-1].t + timedelta(minutes=1)) > STALE:
                self._skip(now, ticker, "no live prices right now (the free feed has no 20:00-4:00 data)")
                continue
            signal, why = check_entry_24(self.plan, ticker, bars, when)
            if not signal:
                self._skip(now, ticker, why)
                continue
            if must_exit_24(self.plan, now, now + timedelta(minutes=15)):
                self._skip(now, ticker, "too close to the session close to open a trade")
                continue
            qty = self.rules.size(equity, signal.entry, signal.stop)
            if qty < 1:
                self._skip(now, ticker, "position too small for account")
                continue
            self.broker.buy(ticker, qty, signal.entry, signal.stop, signal.target, at=now)
            entry = {**asdict(signal), "time": signal.time.isoformat(), "qty": qty, "initial_stop": signal.stop, "news": art["title"]}
            self.book[ticker] = entry
            traded.add(ticker)
            self.traded[day].add(ticker)
            self.log("entry", now, **entry)
