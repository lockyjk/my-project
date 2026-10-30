"""Ticker extraction, catalyst tagging, sentiment and ranking."""

from __future__ import annotations

import math
import re
from datetime import datetime, timezone

from .models import Article

# --- tickers ---------------------------------------------------------------

_CASHTAG = re.compile(r"(?<![\w$])\$([A-Z]{1,5}(?:\.[A-Z])?)\b")
_EXCHANGE = re.compile(
    r"\((?:NASDAQ|NYSE(?:\s+American|\s+Arca)?|AMEX|OTC(?:QB|QX|\s+Markets)?|TSX|CBOE|BATS)\s*:\s*([A-Z]{1,5}(?:\.[A-Z])?)\)",
    re.I,
)
# Capitalised words that look like tickers but almost never are in headlines.
_NOT_TICKERS = {
    "A", "I", "AI", "CEO", "CFO", "COO", "CTO", "IPO", "ETF", "SEC", "FDA", "FED", "GDP", "CPI", "PPI",
    "EPS", "USA", "US", "UK", "EU", "AND", "THE", "FOR", "NEW", "ALL", "ARE", "IT", "ON", "AT", "BY",
    "TO", "OF", "OR", "IS", "BE", "SO", "UP", "GO", "DD", "YOLO", "WSB", "ATH", "IMO", "LOL", "EV",
    "Q1", "Q2", "Q3", "Q4", "FY", "YOY", "QOQ", "NYSE", "OTC", "LLC", "INC", "PLC",
}


def extract_tickers(text: str, watchlist: set[str], aliases: dict[str, str]) -> list[str]:
    found: list[str] = []

    def add(sym: str) -> None:
        sym = sym.upper()
        if sym not in found and sym not in _NOT_TICKERS:
            found.append(sym)

    for m in _EXCHANGE.finditer(text):
        add(m.group(1))
    for m in _CASHTAG.finditer(text):
        add(m.group(1))
    lowered = text.lower()
    for name, sym in aliases.items():
        if re.search(rf"\b{re.escape(name.lower())}\b", lowered):
            add(sym)
    # Bare uppercase words only count when they are on the watchlist.
    for sym in watchlist:
        if sym not in _NOT_TICKERS and re.search(rf"(?<![\w$]){re.escape(sym)}(?!\w)", text):
            add(sym)
    return found


# --- catalysts -------------------------------------------------------------

# name -> (weight, pattern). Weight is how hard the news tends to move a stock intraday.
CATALYSTS: dict[str, tuple[float, re.Pattern]] = {
    name: (weight, re.compile(pattern, re.I))
    for name, weight, pattern in [
        ("halt", 3.0, r"\btrading (?:halt|halted|paused)\b|\bhalted\b|\bLULD\b"),
        ("fda", 3.0, r"\bFDA\b|\bPDUFA\b|\bphase (?:1|2|3|i{1,3})\b|\bclinical (?:trial|hold)\b|\bbreakthrough designation\b|\bEUA\b"),
        ("merger", 3.0, r"\b(?:acquir\w*|merger|to buy|buyout|takeover|tender offer|go(?:ing)? private|definitive agreement)\b"),
        ("bankruptcy", 3.0, r"\bbankrupt\w*|\bchapter 11\b|\bgoing concern\b|\bdelist\w*|\bItem 1\.03\b|\bItem 3\.01\b"),
        ("earnings", 2.5, r"\bItem 2\.02\b|\bearnings\b|\bquarterly results\b|\b(?:Q[1-4]|first|second|third|fourth)[- ]quarter\b|\bEPS\b|\brevenue (?:beat|miss)\b|\bbeats?\b.*\bestimates\b|\bmiss(?:es|ed)?\b.*\bestimates\b"),
        ("guidance", 2.5, r"\bguidance\b|\boutlook\b|\b(?:raises|cuts|lowers|reaffirms|withdraws) (?:its )?(?:full[- ]year |annual )?(?:forecast|outlook|guidance)\b|\bpre-?announce"),
        ("offering", 2.5, r"\b(?:public|secondary|registered direct|at-the-market|ATM) offering\b|\bpriced? (?:an? )?offering\b|\bdilut\w*|\bshelf registration\b|\bconvertible notes?\b|\bwarrants?\b|\bItem 3\.02\b|\b424B\d\b|\bS-[13]\b"),
        ("short_report", 2.5, r"\bshort[- ]seller\b|\bshort report\b|\bHindenburg\b|\bMuddy Waters\b|\bCitron\b"),
        ("analyst", 1.8, r"\bupgrade[sd]?\b|\bdowngrade[sd]?\b|\bprice target\b|\binitiat\w* coverage\b|\boverweight\b|\bunderweight\b|\boutperform\b|\bunderperform\b"),
        ("legal", 1.8, r"\blawsuit\b|\bsued?\b|\bsettle\w*|\bSEC (?:probe|charges|investigation)\b|\bDOJ\b|\bsubpoena\b|\bantitrust\b|\bclass action\b|\bfraud\b"),
        ("contract", 1.6, r"\b(?:awarded|wins?|secures?|lands?) (?:an? )?(?:\$[\d.]+\s*(?:million|billion|[mb])\s+)?(?:contract|deal|order)\b|\bpartnership\b|\bcollaboration\b|\blicens(?:e|ing) agreement\b|\bItem 1\.01\b"),
        ("buyback", 1.5, r"\b(?:share|stock) (?:buyback|repurchase)\b|\bbuyback\b|\bspecial dividend\b"),
        ("insider", 1.3, r"\binsider (?:buying|selling|purchase|sale)\b|\bForm 4\b|\b13D\b|\bactivist\b|\bstake\b"),
        ("split", 1.3, r"\b(?:reverse )?(?:stock )?split\b"),
        ("leadership", 1.3, r"\b(?:CEO|CFO|chief executive)\b.*\b(?:resign\w*|step(?:s|ping)? down|depart\w*|fired|ousted|appoint\w*|named)\b|\bItem 5\.02\b"),
        ("macro", 1.5, r"\b(?:Fed(?:eral Reserve)?|FOMC|Powell|rate (?:cut|hike)|interest rates?|CPI|PPI|inflation|jobs report|nonfarm payrolls|unemployment|GDP|tariffs?|treasury yields?)\b"),
        ("sec_filing", 1.2, r"\b8-K\b|\b6-K\b|\bS-1\b|\bS-3\b|\b424B\d\b|\bSC 13[DG]\b|\b10-Q\b|\b10-K\b"),
    ]
}


def tag_catalysts(text: str) -> list[str]:
    return [name for name, (_, pattern) in CATALYSTS.items() if pattern.search(text)]


# --- sentiment -------------------------------------------------------------

_POSITIVE = {
    "beat": 2, "beats": 2, "surge": 2, "surges": 2, "soar": 2, "soars": 2, "jump": 1.5, "jumps": 1.5,
    "rally": 1.5, "rallies": 1.5, "record": 1, "upgrade": 1.5, "upgraded": 1.5, "raises": 1.5,
    "raised": 1, "approval": 2, "approved": 2, "approves": 2, "strong": 1, "growth": 1, "profit": 1,
    "outperform": 1.5, "buy": 0.5, "bullish": 1.5, "gain": 1, "gains": 1, "rises": 1, "climbs": 1,
    "tops": 1.5, "exceeds": 1.5, "breakthrough": 2, "acquire": 1, "buyback": 1, "positive": 1,
    "wins": 1, "awarded": 1.5, "expands": 1, "higher": 0.5, "boost": 1, "boosts": 1,
}
_NEGATIVE = {
    "miss": 2, "misses": 2, "missed": 2, "plunge": 2, "plunges": 2, "tumble": 2, "tumbles": 2,
    "sink": 1.5, "sinks": 1.5, "drop": 1.5, "drops": 1.5, "fall": 1, "falls": 1, "slide": 1.5,
    "slides": 1.5, "downgrade": 1.5, "downgraded": 1.5, "cuts": 1.5, "lowers": 1.5, "weak": 1,
    "loss": 1, "losses": 1, "lawsuit": 1.5, "probe": 1.5, "investigation": 1.5, "fraud": 2.5,
    "bankruptcy": 3, "bankrupt": 3, "default": 2, "recall": 1.5, "halt": 1, "halted": 1,
    "rejects": 2, "rejected": 2, "crl": 2.5, "dilution": 2, "offering": 1, "layoffs": 1,
    "bearish": 1.5, "underperform": 1.5, "sell": 0.5, "warns": 2, "warning": 1.5, "delay": 1,
    "delays": 1, "resigns": 1, "short": 0.5, "lower": 0.5, "slump": 2, "slumps": 2, "crash": 2.5,
}
_NEGATORS = {"not", "no", "never", "without", "fails", "failed", "despite"}
_WORD = re.compile(r"[a-z][a-z'-]*")


def sentiment(text: str) -> float:
    """Lexicon score squashed into [-1, 1]."""
    words = _WORD.findall(text.lower())
    total = 0.0
    for i, word in enumerate(words):
        value = _POSITIVE.get(word, 0) - _NEGATIVE.get(word, 0)
        if not value:
            continue
        if any(w in _NEGATORS for w in words[max(0, i - 3) : i]):
            value = -value
        total += value
    return math.tanh(total / 4)


# --- ranking ---------------------------------------------------------------


def score(article: Article, watchlist: set[str], now: datetime | None = None, half_life_min: float = 60) -> float:
    """How much a day trader should care right now. Decays with age."""
    now = now or datetime.now(timezone.utc)
    age_min = max(0.0, (now - article.published).total_seconds() / 60)
    impact = sum(CATALYSTS[c][0] for c in article.catalysts) or 0.5
    impact *= 1 + abs(article.sentiment)
    if article.tickers:
        impact += 1
    if watchlist.intersection(article.tickers):
        impact *= 1.5
    return round(impact * 0.5 ** (age_min / half_life_min), 3)


def enrich(
    article: Article,
    watchlist: set[str],
    aliases: dict[str, str],
    now: datetime | None = None,
    half_life_min: float = 60,
) -> Article:
    text = article.text
    article.tickers = extract_tickers(text, watchlist, aliases)
    article.catalysts = tag_catalysts(text)
    article.sentiment = round(sentiment(text), 3)
    article.score = score(article, watchlist, now, half_life_min)
    return article
