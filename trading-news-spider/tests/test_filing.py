import json
import re
from pathlib import Path

import pytest

from newsspider.cli import main
from newsspider.fetch import Response
from newsspider.filing import latest_filing_url, parse_filing
from newsspider.report import render

SAMPLE = Path(__file__).parent / "fixtures" / "sample_10k.htm"


@pytest.fixture(scope="module")
def filing():
    return parse_filing(SAMPLE.read_text(), url="https://www.sec.gov/Archives/edgar/data/1/0001/exmp-20260630.htm")


def cell(filing, label, period="cur"):
    return next(r for r in filing.rows if r["label"] == label)[period]["value"]


def test_identity(filing):
    assert (filing.company, filing.ticker, filing.period_end.isoformat()) == ("EXAMPLE CORP", "EXMP", "2026-06-30")


def test_statement_figures(filing):
    assert cell(filing, "Revenue") == 48_210e6
    assert cell(filing, "Revenue", "prior") == 41_355e6
    assert cell(filing, "Net income") == 13_036e6
    assert cell(filing, "EPS (diluted)") == 5.15
    assert cell(filing, "Other income (expense)", "prior") == -188e6
    assert cell(filing, "Investing cash flow") == -9_470e6
    assert cell(filing, "Capital expenditures") == 7_850e6  # payments are positive, shown in parentheses
    assert cell(filing, "Total assets") == 76_759e6
    assert len(filing.rows) == 36


def test_ignores_segment_and_quarter_facts(filing):
    revenue = next(r for r in filing.rows if r["label"] == "Revenue")["cur"]
    assert revenue["value"] == 48_210e6  # not the 21,400 segment or the 13,050 quarter
    assert revenue["page"] == 7  # the income statement, not the MD&A sentence


def test_derived_metrics(filing):
    derived = {d["label"]: d["text"] for d in filing.derived}
    assert derived["Gross margin"] == "58.8%"
    assert derived["Revenue growth (YoY)"] == "+16.6%"
    assert derived["Free cash flow"] == "$10.1B"
    assert derived["Returned to shareholders"] == "$6.5B"


def test_text_figures_and_sections(filing):
    texts = [(f["text"], f["section"], f["page"]) for f in filing.text_figures]
    assert ("$1.1 billion", "Item 3", 4) in texts
    assert ("$6.9 billion", "Item 7", 5) in texts
    assert [s["name"] for s in filing.sections] == ["Item 1", "Item 1A", "Item 3", "Item 7", "Item 7A", "Item 8"]
    assert filing.sections[3]["title"].startswith("Management's Discussion and Analysis")


def test_every_target_exists_in_document(filing):
    ids = set(re.findall(r'id="([^"]+)"', filing.html))
    targets = [c["el"] for r in filing.rows for c in (r.get("cur"), r.get("prior")) if c]
    targets += [f["el"] for f in filing.text_figures] + [s["el"] for s in filing.sections]
    assert set(targets) <= ids


def test_document_is_sanitized(filing):
    assert "<script" not in filing.html.lower()
    assert "xbrli:context" not in filing.html.lower()


def test_render_embeds_data_safely(filing):
    page = render(filing, caption="Spider <test>")
    assert "__DATA__" not in page and "__DOCUMENT__" not in page
    assert "Spider &lt;test&gt;" in page
    data = json.loads(re.search(r'<script type="application/json" id="sp-data">(.*?)</script>', page, re.S).group(1))
    assert data["ticker"] == "EXMP" and data["fyCur"] == "FY2026"


def test_rejects_non_xbrl():
    with pytest.raises(RuntimeError, match="inline-XBRL"):
        parse_filing("<html><body>plain</body></html>")


class FakeFetcher:
    def __init__(self, routes):
        self.routes = routes

    def get(self, url, respect_robots=True):
        return Response(url, 200, self.routes[url]) if url in self.routes else None


def test_latest_filing_url():
    fetcher = FakeFetcher({
        "https://www.sec.gov/files/company_tickers.json": json.dumps({"0": {"cik_str": 789019, "ticker": "MSFT", "title": "MICROSOFT CORP"}}),
        "https://data.sec.gov/submissions/CIK0000789019.json": json.dumps({"filings": {"recent": {
            "form": ["8-K", "10-Q", "10-K", "10-K"],
            "accessionNumber": ["0-1", "0-2", "0000950170-26-000001", "0-4"],
            "primaryDocument": ["a.htm", "b.htm", "msft-20260630.htm", "old.htm"],
        }}}),
    })
    url, company = latest_filing_url(fetcher, "msft")
    assert url == "https://www.sec.gov/Archives/edgar/data/789019/000095017026000001/msft-20260630.htm"
    assert company == "MICROSOFT CORP"


def test_cli_filing_from_file(tmp_path, capsys):
    cfg = tmp_path / "config.toml"
    cfg.write_text(f'user_agent = "t"\ndatabase = "{tmp_path / "news.db"}"\n')
    out = tmp_path / "spider.html"
    main(["-c", str(cfg), "filing", "--file", str(SAMPLE), "-o", str(out)])
    assert "36 statement figures" in capsys.readouterr().out
    assert 'id="sp-overlay"' in out.read_text()
