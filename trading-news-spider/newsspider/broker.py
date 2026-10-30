"""Where orders go: a local paper account by default, or Alpaca (paper or live)."""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

import requests


@dataclass
class Position:
    ticker: str
    qty: int
    entry: float
    stop: float
    target: float
    opened: str
    at_breakeven: bool = False


class PaperBroker:
    """Simulated account kept in a JSON file. The bot manages stops and targets itself each minute."""

    name = "local paper"

    def __init__(self, path: str | Path, starting_cash: float = 100_000):
        self.path = Path(path)
        if self.path.exists():
            state = json.loads(self.path.read_text())
        else:
            state = {"cash": starting_cash, "positions": {}, "fills": []}
        self.cash: float = state["cash"]
        self.positions = {k: Position(**v) for k, v in state["positions"].items()}
        self.fills: list[dict] = state["fills"]

    def _save(self) -> None:
        state = {"cash": self.cash, "positions": {k: asdict(p) for k, p in self.positions.items()}, "fills": self.fills}
        self.path.write_text(json.dumps(state, indent=2))

    def equity(self, prices: dict[str, float] | None = None) -> float:
        prices = prices or {}
        return self.cash + sum(p.qty * prices.get(p.ticker, p.entry) for p in self.positions.values())

    def buy(self, ticker: str, qty: int, price: float, stop: float, target: float, at: datetime | None = None) -> None:
        self.cash -= qty * price
        self.positions[ticker] = Position(ticker, qty, price, stop, target, (at or datetime.now(timezone.utc)).isoformat())
        self.fills.append({"side": "buy", "ticker": ticker, "qty": qty, "price": price, "at": self.positions[ticker].opened})
        self._save()

    def sell(self, ticker: str, price: float, reason: str, at: datetime | None = None) -> float:
        pos = self.positions.pop(ticker)
        self.cash += pos.qty * price
        pnl = pos.qty * (price - pos.entry)
        self.fills.append({"side": "sell", "ticker": ticker, "qty": pos.qty, "price": price, "pnl": round(pnl, 2),
                           "reason": reason, "at": (at or datetime.now(timezone.utc)).isoformat()})
        self._save()
        return pnl

    def sell_part(self, ticker: str, qty: int, price: float, reason: str, at: datetime | None = None) -> float:
        pos = self.positions[ticker]
        qty = min(qty, pos.qty)
        if qty >= pos.qty:
            return self.sell(ticker, price, reason, at)
        pos.qty -= qty
        self.cash += qty * price
        pnl = qty * (price - pos.entry)
        self.fills.append({"side": "sell", "ticker": ticker, "qty": qty, "price": price, "pnl": round(pnl, 2),
                           "reason": reason, "at": (at or datetime.now(timezone.utc)).isoformat()})
        self._save()
        return pnl

    def move_stop(self, ticker: str, stop: float) -> None:
        self.positions[ticker].stop = stop
        self.positions[ticker].at_breakeven = True
        self._save()

    def day_pnl(self, day: str) -> float:
        return sum(f.get("pnl", 0) for f in self.fills if f["side"] == "sell" and f["at"][:10] == day)

    def traded_today(self, day: str) -> set[str]:
        return {f["ticker"] for f in self.fills if f["side"] == "buy" and f["at"][:10] == day}


class AlpacaBroker:
    """Alpaca REST API. Bracket orders put the stop and target on Alpaca's servers, so they hold even if
    this program stops. Keys come from ALPACA_API_KEY_ID / ALPACA_API_SECRET_KEY."""

    PAPER = "https://paper-api.alpaca.markets"
    LIVE = "https://api.alpaca.markets"

    def __init__(self, live: bool = False, session: requests.Session | None = None):
        key, secret = os.environ.get("ALPACA_API_KEY_ID"), os.environ.get("ALPACA_API_SECRET_KEY")
        if not key or not secret:
            raise RuntimeError("set ALPACA_API_KEY_ID and ALPACA_API_SECRET_KEY (from your Alpaca dashboard)")
        self.base = self.LIVE if live else self.PAPER
        self.name = "Alpaca LIVE" if live else "Alpaca paper"
        self.http = session or requests.Session()
        self.http.headers.update({"APCA-API-KEY-ID": key, "APCA-API-SECRET-KEY": secret})

    def _call(self, method: str, path: str, **kwargs):
        resp = self.http.request(method, self.base + path, timeout=15, **kwargs)
        if resp.status_code >= 400:
            raise RuntimeError(f"Alpaca {method} {path} failed: {resp.status_code} {resp.text[:200]}")
        return resp.json() if resp.text else None

    def clock(self) -> dict:
        return self._call("GET", "/v2/clock")

    def equity(self, prices: dict[str, float] | None = None) -> float:
        return float(self._call("GET", "/v2/account")["equity"])

    @property
    def positions(self) -> dict[str, Position]:
        out = {}
        for p in self._call("GET", "/v2/positions"):
            out[p["symbol"]] = Position(p["symbol"], int(float(p["qty"])), float(p["avg_entry_price"]), 0.0, 0.0, "")
        return out

    def buy(self, ticker: str, qty: int, price: float, stop: float, target: float, at: datetime | None = None) -> None:
        self._call("POST", "/v2/orders", json={
            "symbol": ticker, "qty": str(qty), "side": "buy", "type": "market", "time_in_force": "day",
            "order_class": "bracket",
            "take_profit": {"limit_price": f"{target:.2f}"},
            "stop_loss": {"stop_price": f"{stop:.2f}"},
        })

    def sell(self, ticker: str, price: float, reason: str, at: datetime | None = None) -> float:
        self._call("DELETE", f"/v2/positions/{ticker}", params={"cancel_orders": "true"})
        return 0.0

    def move_stop(self, ticker: str, stop: float) -> None:
        for order in self._call("GET", "/v2/orders", params={"status": "open", "symbols": ticker, "nested": "true"}):
            for leg in [order, *(order.get("legs") or [])]:
                if leg.get("type") == "stop" and leg.get("status") in ("new", "accepted", "held"):
                    self._call("PATCH", f"/v2/orders/{leg['id']}", json={"stop_price": f"{stop:.2f}"})

    def day_pnl(self, day: str) -> float:
        account = self._call("GET", "/v2/account")
        return float(account["equity"]) - float(account["last_equity"])

    def traded_today(self, day: str) -> set[str]:
        orders = self._call("GET", "/v2/orders", params={"status": "all", "after": f"{day}T00:00:00Z", "side": "buy", "limit": 500})
        return {o["symbol"] for o in orders}
