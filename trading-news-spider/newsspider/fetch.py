"""Polite HTTP: robots.txt, per-host rate limits, conditional GETs and retries."""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from urllib.parse import urlsplit
from urllib.robotparser import RobotFileParser

import requests

log = logging.getLogger(__name__)


@dataclass
class Response:
    url: str
    status: int
    text: str


class Fetcher:
    def __init__(self, user_agent: str, min_interval: float = 2.0, timeout: float = 15.0, retries: int = 3):
        self.user_agent = user_agent
        self.min_interval = min_interval
        self.timeout = timeout
        self.retries = retries
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": user_agent, "Accept-Encoding": "gzip, deflate"})
        self._robots: dict[str, RobotFileParser | None] = {}
        self._last_hit: dict[str, float] = {}
        self._validators: dict[str, dict[str, str]] = {}  # url -> ETag / Last-Modified
        self._lock = threading.Lock()

    def _allowed(self, url: str) -> bool:
        parts = urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        if origin not in self._robots:
            parser = RobotFileParser()
            try:
                resp = self.session.get(f"{origin}/robots.txt", timeout=self.timeout)
                if resp.status_code >= 400:
                    parser = None  # no robots.txt means no restrictions
                else:
                    parser.parse(resp.text.splitlines())
            except requests.RequestException:
                parser = None
            self._robots[origin] = parser
        parser = self._robots[origin]
        return parser is None or parser.can_fetch(self.user_agent, url)

    def _throttle(self, host: str) -> None:
        with self._lock:
            wait = self._last_hit.get(host, 0) + self.min_interval - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self._last_hit[host] = time.monotonic()

    def get(self, url: str, respect_robots: bool = True) -> Response | None:
        """Returns None when disallowed, unchanged since last fetch (304) or failing."""
        if respect_robots and not self._allowed(url):
            log.warning("robots.txt disallows %s, skipping", url)
            return None
        host = urlsplit(url).netloc
        headers = dict(self._validators.get(url, {}))
        for attempt in range(1, self.retries + 1):
            self._throttle(host)
            try:
                resp = self.session.get(url, headers=headers, timeout=self.timeout)
            except requests.RequestException as exc:
                log.warning("fetch %s failed (attempt %d): %s", url, attempt, exc)
                time.sleep(2**attempt)
                continue
            if resp.status_code == 304:
                return None
            if resp.status_code in (429, 500, 502, 503, 504):
                delay = float(resp.headers.get("Retry-After", 2**attempt)) if resp.headers.get("Retry-After", "").isdigit() else 2**attempt
                log.warning("fetch %s got %d, backing off %.0fs", url, resp.status_code, delay)
                time.sleep(delay)
                continue
            if resp.status_code >= 400:
                log.warning("fetch %s got %d", url, resp.status_code)
                return None
            validators = {}
            if etag := resp.headers.get("ETag"):
                validators["If-None-Match"] = etag
            if modified := resp.headers.get("Last-Modified"):
                validators["If-Modified-Since"] = modified
            self._validators[url] = validators
            return Response(url=url, status=resp.status_code, text=resp.text)
        return None
