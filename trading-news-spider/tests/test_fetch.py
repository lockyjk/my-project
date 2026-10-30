import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from newsspider.fetch import Fetcher


class Handler(BaseHTTPRequestHandler):
    hits: dict[str, int] = {}

    def log_message(self, *args):
        pass

    def do_GET(self):
        Handler.hits[self.path] = Handler.hits.get(self.path, 0) + 1
        if self.path == "/robots.txt":
            self._send(200, "User-agent: *\nDisallow: /private\n")
        elif self.path == "/feed":
            if self.headers.get("If-None-Match") == '"v1"':
                self._send(304, "")
            else:
                self._send(200, "<rss/>", {"ETag": '"v1"'})
        elif self.path == "/flaky" and Handler.hits[self.path] == 1:
            self._send(503, "busy", {"Retry-After": "0"})
        elif self.path == "/flaky":
            self._send(200, "ok")
        else:
            self._send(404, "")

    def _send(self, status, body, headers=None):
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body.encode())


@pytest.fixture
def base():
    Handler.hits = {}
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{server.server_port}"
    server.shutdown()


@pytest.fixture
def fetcher(monkeypatch):
    f = Fetcher("test-agent", min_interval=0)
    f.session.trust_env = False  # talk to the local server directly, not via any proxy
    return f


def test_robots_disallow_is_respected(base, fetcher):
    assert fetcher.get(f"{base}/private/x") is None
    assert "/private/x" not in Handler.hits


def test_conditional_get_returns_none_when_unchanged(base, fetcher):
    assert fetcher.get(f"{base}/feed").text == "<rss/>"
    assert fetcher.get(f"{base}/feed") is None
    assert Handler.hits["/feed"] == 2


def test_retries_after_503(base, fetcher):
    assert fetcher.get(f"{base}/flaky").text == "ok"
    assert Handler.hits["/flaky"] == 2


def test_404_returns_none(base, fetcher):
    assert fetcher.get(f"{base}/missing") is None
