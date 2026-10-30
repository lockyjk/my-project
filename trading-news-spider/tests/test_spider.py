from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from pathlib import Path

import pytest

from newsspider.cli import main
from newsspider.enrich import extract_tickers, sentiment, tag_catalysts
from newsspider.fetch import Response
from newsspider.models import normalize_url
from newsspider.parse import parse_reddit
from newsspider.quotes import parse_chart
from newsspider.spider import SEC_TICKERS_URL, Config, Spider
from newsspider.store import Store

FIXTURES = Path(__file__).parent / "fixtures"
NOW = datetime.now(timezone.utc).replace(microsecond=0)


def fixture(name: str) -> str:
    text = (FIXTURES / name).read_text()
    for minutes in (4, 5, 10, 20, 30, 40):
        when = NOW - timedelta(minutes=minutes)
        stamp = when.isoformat() if name.endswith(".atom") else format_datetime(when)
        text = text.replace(f"{{MIN{minutes}}}", stamp)
    text = text.replace("{DAYS3}", format_datetime(NOW - timedelta(days=3)))
    return text.replace("{EPOCH}", str(int(NOW.timestamp())))


class FakeFetcher:
    def __init__(self, routes: dict[str, str]):
        self.routes = routes

    def get(self, url, respect_robots=True):
        name = self.routes.get(url)
        return Response(url, 200, fixture(name)) if name else None


def make_spider(tmp_path, sources) -> Spider:
    config = Config(
        user_agent="test",
        database=str(tmp_path / "news.db"),
        watchlist=["NVDA", "TSLA", "AMD"],
        aliases={"Nvidia": "NVDA", "Tesla": "TSLA"},
        sources=sources,
    )
    routes = {s["url"]: s["fixture"] for s in sources}
    routes[SEC_TICKERS_URL] = "company_tickers.json"
    return Spider(config, store=Store(config.database), fetcher=FakeFetcher(routes))


# --- unit -------------------------------------------------------------------


def test_normalize_url_strips_tracking():
    assert normalize_url("HTTPS://Example.com/a/?utm_source=x&id=7#frag") == "https://example.com/a?id=7"


def test_extract_tickers_sources():
    text = "Acme (NASDAQ: ACME) and $XYZ rally; Nvidia too. CEO says AI is big. TSLA flat."
    tickers = extract_tickers(text, {"TSLA"}, {"Nvidia": "NVDA"})
    assert tickers == ["ACME", "XYZ", "NVDA", "TSLA"]


def test_bare_caps_only_count_on_watchlist():
    assert extract_tickers("THE CEO OF IBM spoke", set(), {}) == []


def test_catalysts():
    assert "fda" in tag_catalysts("FDA grants approval")
    assert "offering" in tag_catalysts("prices $5M registered direct offering")
    assert "analyst" in tag_catalysts("Goldman upgrades stock, raises price target")
    assert "merger" in tag_catalysts("Company to be acquired in definitive agreement")
    assert tag_catalysts("Weather is nice today") == []


def test_sentiment_direction_and_negation():
    assert sentiment("Shares surge after earnings beat") > 0.5
    assert sentiment("Stock plunges after guidance cut and fraud probe") < -0.5
    assert sentiment("Company did not beat estimates") < 0


def test_parse_reddit_skips_stickied():
    posts = parse_reddit("wsb", fixture("reddit.json"))
    assert [p.title for p in posts] == ["$TSLA calls printing after delivery beat"]


def test_parse_chart():
    quote = parse_chart("NVDA", fixture("chart.json"))
    assert quote.change_pct == 10.0 and quote.volume == 3500


# --- pipeline ---------------------------------------------------------------


def test_crawl_end_to_end(tmp_path):
    spider = make_spider(
        tmp_path,
        [
            {"name": "Markets", "kind": "rss", "url": "https://a.test/rss", "fixture": "market.rss"},
            {"name": "Wire", "kind": "rss", "url": "https://b.test/rss", "fixture": "syndicated.rss"},
            {"name": "SEC", "kind": "sec", "url": "https://sec.test/atom", "fixture": "sec.atom"},
        ],
    )
    fresh = spider.crawl()
    titles = [a.title for a in fresh]

    assert not any("Old story" in t for t in titles), "items older than max_age are dropped"
    assert sum("Nvidia" in t for t in titles) == 1, "syndicated copy is de-duplicated"

    by_title = {a.title: a for a in fresh}
    nvda = next(a for a in fresh if "Nvidia" in a.title)
    assert nvda.tickers == ["NVDA"]
    assert {"earnings", "guidance"} <= set(nvda.catalysts)
    assert nvda.sentiment > 0.5

    sec = next(a for a in fresh if a.title.startswith("8-K"))
    assert sec.tickers == ["AMD"], "SEC filer CIK resolves to a ticker"

    assert by_title["Tiny Corp prices $20 million registered direct offering"].sentiment < 0
    assert fresh[0].score >= fresh[-1].score

    # Second crawl finds nothing new, and the duplicate was recorded as corroboration.
    assert spider.crawl() == []
    top = spider.store.recent(timedelta(hours=1), ticker="NVDA")
    assert top[0]["sources"] == ["Markets", "Wire"]

    heat = spider.store.ticker_heat(timedelta(hours=1))
    assert heat[0]["ticker"] in {"NVDA", "ACMB"}


def test_per_ticker_sources_expand():
    config = Config(user_agent="t", watchlist=["AAA", "BBB"], sources=[
        {"name": "Y", "url": "https://y.test/{ticker}", "per_ticker": True},
        {"name": "Off", "url": "https://off.test", "enabled": False},
    ])
    assert [url for _, url in config.targets()] == ["https://y.test/AAA", "https://y.test/BBB"]


def test_bundled_config_loads():
    config = Config.load(Path(__file__).parent.parent / "config.toml")
    assert config.watchlist and config.targets()
    assert all("{ticker}" not in url for _, url in config.targets())


def test_cli_top_and_export(tmp_path, capsys, monkeypatch):
    spider = make_spider(tmp_path, [{"name": "Markets", "kind": "rss", "url": "https://a.test/rss", "fixture": "market.rss"}])
    spider.crawl()
    cfg = tmp_path / "config.toml"
    cfg.write_text(f'user_agent = "t"\ndatabase = "{tmp_path / "news.db"}"\n')
    main(["-c", str(cfg), "top", "--since", "2h"])
    assert "Nvidia" in capsys.readouterr().out
    out = tmp_path / "out.csv"
    main(["-c", str(cfg), "export", "--since", "2h", "-o", str(out)])
    assert "Acme Bio" in out.read_text()


@pytest.mark.parametrize("bad", ["2", "h", "5w"])
def test_duration_rejects_bad_input(bad):
    from newsspider.cli import duration
    import argparse

    with pytest.raises(argparse.ArgumentTypeError):
        duration(bad)
