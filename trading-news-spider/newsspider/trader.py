"""The live loop: each minute, manage open trades, then look for new entries from the spider's news."""

from __future__ import annotations

import json
import time as clock
from dataclasses import asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable

from .bars import ET, OPEN, Bar, by_session
from .broker import PaperBroker
from .risk import RiskRules
from .strategy import Plan, _t, check_entry, qualifying_news


class Trader:
    def __init__(
        self,
        plan: Plan,
        rules: RiskRules,
        broker,
        bars: Callable[[str], list[Bar]],
        news: Callable[[], list[dict]],
        journal: str | Path = "bot_journal.jsonl",
    ):
        self.plan, self.rules, self.broker = plan, rules, broker
        self.bars, self.news = bars, news
        self.journal = Path(journal)
        self.traded: dict[str, set[str]] = {}  # ET date -> tickers entered that day
        self.book: dict[str, dict] = self._load_book()  # ticker -> entry/stop/target/breakeven for open trades
        self.said: set[str] = set()  # skip reasons already logged, to keep the log quiet

    # --- journal ---------------------------------------------------------------

    def _load_book(self) -> dict[str, dict]:
        book: dict[str, dict] = {}
        if self.journal.exists():
            for line in self.journal.read_text().splitlines():
                event = json.loads(line)
                if event["event"] == "entry":
                    book[event["ticker"]] = event
                    self.traded.setdefault(event["at"][:10], set()).add(event["ticker"])
                elif event["event"] == "exit":
                    book.pop(event["ticker"], None)
                elif event["event"] == "breakeven" and event["ticker"] in book:
                    book[event["ticker"]]["stop"], book[event["ticker"]]["at_breakeven"] = event["stop"], True
        return book

    def log(self, event: str, now: datetime, **data) -> str:
        record = {"event": event, "at": now.isoformat(), **data}
        with self.journal.open("a") as f:
            f.write(json.dumps(record, default=str) + "\n")
        line = f"{now:%H:%M} {event.upper():<9} " + " ".join(f"{k}={v}" for k, v in data.items() if k not in ("news",))
        print(line, flush=True)
        return line

    # --- one minute of work ------------------------------------------------------

    def tick(self, now: datetime) -> None:
        now = now.astimezone(ET)
        if now.weekday() >= 5 or not (OPEN <= now.time() < _t("16:00")):
            return
        day = now.date().isoformat()
        prices = self._manage_open(now)
        if _t(self.plan.entry_start) <= now.time() < _t(self.plan.entry_end):
            self._look_for_entries(now, day, prices)

    def _today(self, ticker: str, now: datetime) -> tuple[list[Bar], list[list[Bar]]]:
        sessions = by_session(self.bars(ticker))
        today = [b for b in sessions.get(now.date(), []) if b.t + timedelta(minutes=1) <= now]
        history = [bars for d, bars in sorted(sessions.items()) if d < now.date()]
        return today, history

    def _manage_open(self, now: datetime) -> dict[str, float]:
        prices = {}
        exit_at = _t(self.plan.exit_time)
        for ticker in list(self.broker.positions):
            today, _ = self._today(ticker, now)
            if not today:
                continue
            last = today[-1]
            prices[ticker] = last.c
            lvl = self.book.get(ticker)
            if now.time() >= exit_at:
                pnl = self.broker.sell(ticker, last.c, "time exit", at=now)
                self.log("exit", now, ticker=ticker, price=last.c, reason="time exit", pnl=round(pnl, 2))
                self.book.pop(ticker, None)
                continue
            if lvl:  # positions the bot did not open are left alone
                self._check_levels(ticker, last, lvl, now)
        return prices

    def _check_levels(self, ticker: str, last: Bar, lvl: dict, now: datetime) -> None:
        """Stop, target and breakeven for one open trade, judged on the latest bar."""
        local = isinstance(self.broker, PaperBroker)  # Alpaca brackets fill stops and targets themselves
        if local and last.l <= lvl["stop"]:
            price = min(lvl["stop"], last.o)
            why = "breakeven stop" if lvl.get("at_breakeven") else "stop"
        elif local and last.h >= lvl["target"]:
            price, why = max(lvl["target"], last.o), "target"
        else:
            risk = lvl["entry"] - lvl["initial_stop"]
            if not lvl.get("at_breakeven") and last.h >= lvl["entry"] + self.plan.breakeven_r * risk:
                self.broker.move_stop(ticker, lvl["entry"])
                lvl["stop"], lvl["at_breakeven"] = lvl["entry"], True
                self.log("breakeven", now, ticker=ticker, stop=lvl["entry"])
            return
        pnl = self.broker.sell(ticker, price, why, at=now)
        self.log("exit", now, ticker=ticker, price=round(price, 4), reason=why, pnl=round(pnl, 2))
        self.book.pop(ticker, None)

    def _look_for_entries(self, now: datetime, day: str, prices: dict[str, float]) -> None:
        candidates = {t: art for (t, session), art in qualifying_news(self.news(), self.plan).items() if session == now.date()}
        if not candidates:
            return
        equity = self.broker.equity(prices)
        traded = self.traded.setdefault(day, set()) | self.broker.traded_today(day)
        for ticker, art in candidates.items():
            ok, why = self.rules.can_open(ticker, set(self.broker.positions), traded, self.broker.day_pnl(day), equity)
            if not ok:
                self._skip(now, ticker, why)
                if "daily loss" in why:
                    return
                continue
            today, history = self._today(ticker, now)
            if today and now - (today[-1].t + timedelta(minutes=1)) > timedelta(minutes=3):
                self._skip(now, ticker, "price data is stale")
                continue
            signal, why = check_entry(self.plan, ticker, today, history, art["published_at"])
            if not signal:
                self._skip(now, ticker, why)
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

    def _skip(self, now: datetime, ticker: str, why: str) -> None:
        key = f"{now.date()}|{ticker}|{why.split(' ')[0]}"
        if key not in self.said:
            self.said.add(key)
            self.log("skip", now, ticker=ticker, reason=why)

    # --- forever ------------------------------------------------------------------

    def run(self, crawl: Callable[[], object], poll_seconds: int = 60, market_open: Callable[[], bool] | None = None) -> None:
        print(f"bot running on {self.broker.name}; Ctrl+C to stop")
        while True:
            started = clock.monotonic()
            now = datetime.now(ET)
            if market_open is None or market_open():
                crawl()
                self.tick(now)
            clock.sleep(max(5, poll_seconds - (clock.monotonic() - started)))
