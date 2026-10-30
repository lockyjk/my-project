"""Price context for tickers in the news (Yahoo's public chart endpoint, unofficial)."""

from __future__ import annotations

import json
from dataclasses import dataclass

from .fetch import Fetcher

CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?interval=1m&range=1d&includePrePost=true"


@dataclass
class Quote:
    ticker: str
    price: float
    prev_close: float
    volume: int

    @property
    def change_pct(self) -> float:
        return round((self.price / self.prev_close - 1) * 100, 2) if self.prev_close else 0.0


def parse_chart(ticker: str, payload: str) -> Quote | None:
    try:
        result = json.loads(payload)["chart"]["result"][0]
        meta = result["meta"]
        volumes = result.get("indicators", {}).get("quote", [{}])[0].get("volume") or []
        return Quote(
            ticker=ticker,
            price=float(meta["regularMarketPrice"]),
            prev_close=float(meta.get("chartPreviousClose") or meta.get("previousClose") or 0),
            volume=int(sum(v for v in volumes if v)),
        )
    except (KeyError, IndexError, TypeError, ValueError):
        return None


def get_quotes(fetcher: Fetcher, tickers: list[str]) -> dict[str, Quote]:
    quotes = {}
    for ticker in tickers:
        resp = fetcher.get(CHART_URL.format(ticker=ticker))
        if resp and (quote := parse_chart(ticker, resp.text)):
            quotes[ticker] = quote
    return quotes
