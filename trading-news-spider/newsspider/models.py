from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

# Query params that only track clicks and never change the article.
_TRACKING_PARAMS = re.compile(r"^(utm_|mc_|fbclid|gclid|cmpid|ref|src|.tsrc|guccounter)", re.I)


def normalize_url(url: str) -> str:
    parts = urlsplit(url.strip())
    query = [(k, v) for k, v in parse_qsl(parts.query) if not _TRACKING_PARAMS.match(k)]
    path = parts.path.rstrip("/") or "/"
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, urlencode(query), ""))


def title_key(title: str) -> str:
    """Fingerprint for spotting the same story syndicated under different URLs."""
    words = re.findall(r"[a-z0-9]+", title.lower())
    return hashlib.sha1(" ".join(words).encode()).hexdigest()


@dataclass
class Article:
    source: str
    title: str
    url: str
    published: datetime
    summary: str = ""
    tickers: list[str] = field(default_factory=list)
    catalysts: list[str] = field(default_factory=list)
    sentiment: float = 0.0
    score: float = 0.0

    def __post_init__(self) -> None:
        self.url = normalize_url(self.url)
        if self.published.tzinfo is None:
            self.published = self.published.replace(tzinfo=timezone.utc)

    @property
    def uid(self) -> str:
        return hashlib.sha1(self.url.encode()).hexdigest()

    @property
    def title_key(self) -> str:
        return title_key(self.title)

    @property
    def text(self) -> str:
        return f"{self.title}\n{self.summary}"
