"""Read a 10-K/10-Q's inline XBRL: locate every key figure in the document for the spider to visit."""

from __future__ import annotations

import json
import re
import warnings
from dataclasses import dataclass, field
from datetime import date, timedelta
from urllib.parse import urljoin

from bs4 import BeautifulSoup, NavigableString, Tag, XMLParsedAsHTMLWarning

from .fetch import Fetcher

SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik}.json"
ARCHIVE_URL = "https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/{document}"
TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"

# (section, label, kind, candidate us-gaap concepts in order of preference)
ROWS: list[tuple[str, str, str, list[str]]] = [
    ("Income statement", "Revenue", "usd", ["RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues", "SalesRevenueNet", "RevenueFromContractWithCustomerIncludingAssessedTax"]),
    ("Income statement", "Cost of revenue", "usd", ["CostOfRevenue", "CostOfGoodsAndServicesSold", "CostOfGoodsSold"]),
    ("Income statement", "Gross profit", "usd", ["GrossProfit"]),
    ("Income statement", "Research and development", "usd", ["ResearchAndDevelopmentExpense", "ResearchAndDevelopmentExpenseExcludingAcquiredInProcessCost"]),
    ("Income statement", "Sales and marketing", "usd", ["SellingAndMarketingExpense", "SellingGeneralAndAdministrativeExpense"]),
    ("Income statement", "General and administrative", "usd", ["GeneralAndAdministrativeExpense"]),
    ("Income statement", "Operating income", "usd", ["OperatingIncomeLoss"]),
    ("Income statement", "Other income (expense)", "usd", ["NonoperatingIncomeExpense", "OtherNonoperatingIncomeExpense"]),
    ("Income statement", "Income before taxes", "usd", ["IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest", "IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments"]),
    ("Income statement", "Income taxes", "usd", ["IncomeTaxExpenseBenefit"]),
    ("Income statement", "Net income", "usd", ["NetIncomeLoss", "ProfitLoss", "NetIncomeLossAvailableToCommonStockholdersBasic"]),
    ("Income statement", "EPS (basic)", "eps", ["EarningsPerShareBasic"]),
    ("Income statement", "EPS (diluted)", "eps", ["EarningsPerShareDiluted", "EarningsPerShareBasicAndDiluted"]),
    ("Income statement", "Shares (basic)", "shares", ["WeightedAverageNumberOfSharesOutstandingBasic"]),
    ("Income statement", "Shares (diluted)", "shares", ["WeightedAverageNumberOfDilutedSharesOutstanding"]),
    ("Balance sheet", "Cash and equivalents", "usd", ["CashAndCashEquivalentsAtCarryingValue", "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents"]),
    ("Balance sheet", "Short-term investments", "usd", ["ShortTermInvestments", "AvailableForSaleSecuritiesDebtSecuritiesCurrent", "MarketableSecuritiesCurrent"]),
    ("Balance sheet", "Accounts receivable", "usd", ["AccountsReceivableNetCurrent", "ReceivablesNetCurrent"]),
    ("Balance sheet", "Inventories", "usd", ["InventoryNet"]),
    ("Balance sheet", "Total current assets", "usd", ["AssetsCurrent"]),
    ("Balance sheet", "Property and equipment", "usd", ["PropertyPlantAndEquipmentNet", "PropertyPlantAndEquipmentAndFinanceLeaseRightOfUseAssetAfterAccumulatedDepreciationAndAmortization"]),
    ("Balance sheet", "Goodwill", "usd", ["Goodwill"]),
    ("Balance sheet", "Total assets", "usd", ["Assets"]),
    ("Balance sheet", "Accounts payable", "usd", ["AccountsPayableCurrent"]),
    ("Balance sheet", "Total current liabilities", "usd", ["LiabilitiesCurrent"]),
    ("Balance sheet", "Long-term debt", "usd", ["LongTermDebtNoncurrent", "LongTermDebt"]),
    ("Balance sheet", "Total liabilities", "usd", ["Liabilities"]),
    ("Balance sheet", "Stockholders' equity", "usd", ["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"]),
    ("Cash flow statement", "Operating cash flow", "usd", ["NetCashProvidedByUsedInOperatingActivities"]),
    ("Cash flow statement", "Depreciation and amortization", "usd", ["DepreciationDepletionAndAmortization", "DepreciationAmortizationAndOther", "DepreciationAndAmortization"]),
    ("Cash flow statement", "Stock-based compensation", "usd", ["ShareBasedCompensation", "AllocatedShareBasedCompensationExpense"]),
    ("Cash flow statement", "Capital expenditures", "usd", ["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets"]),
    ("Cash flow statement", "Investing cash flow", "usd", ["NetCashProvidedByUsedInInvestingActivities"]),
    ("Cash flow statement", "Share buybacks", "usd", ["PaymentsForRepurchaseOfCommonStock"]),
    ("Cash flow statement", "Dividends paid", "usd", ["PaymentsOfDividendsCommonStock", "PaymentsOfDividends"]),
    ("Cash flow statement", "Financing cash flow", "usd", ["NetCashProvidedByUsedInFinancingActivities"]),
]

_TEXT_FIGURE = re.compile(r"\$\s?\d{1,3}(?:,\d{3})*(?:\.\d+)?\s?(?:million|billion|trillion)\b", re.I)
_ITEM_HEADING = re.compile(r"^\s*item\s+(\d{1,2}[a-c]?)\s*[.:\-–—]?\s*(.{0,200})$", re.I | re.S)
_SMALL_WORDS = {"and", "of", "the", "for", "on", "in", "to", "a", "an", "or", "about"}
_PAGE_BREAK = re.compile(r"page-break-(?:after|before)\s*:\s*always|break-(?:after|before)\s*:\s*page", re.I)
_UNSAFE_TAGS = ("script", "iframe", "object", "embed", "link", "meta", "base", "form", "noscript")
MAX_TEXT_FIGURES = 24


def _title(text: str) -> str:
    """Item headings are often ALL CAPS; make them Title Case with small words lowered."""
    words = []
    for i, word in enumerate(re.sub(r"\s+", " ", text).strip(" .").split(" ")):
        if i and word.lower() in _SMALL_WORDS:
            word = word.lower()
        elif word.isupper() or word.islower():
            word = word.capitalize()
        words.append(word)
    return " ".join(words)


def _local(name: str | None) -> str:
    return (name or "").rsplit(":", 1)[-1].lower()


@dataclass
class Period:
    start: date | None
    end: date

    @property
    def days(self) -> int:
        return (self.end - self.start).days if self.start else 0


@dataclass
class Fact:
    concept: str
    value: float
    period: Period
    tag: Tag
    in_table: bool
    order: int


@dataclass
class Filing:
    company: str
    ticker: str
    form: str
    period_end: date
    url: str
    rows: list[dict] = field(default_factory=list)
    derived: list[dict] = field(default_factory=list)
    text_figures: list[dict] = field(default_factory=list)
    sections: list[dict] = field(default_factory=list)
    html: str = ""

    def data(self) -> dict:
        return {
            "company": self.company, "ticker": self.ticker, "form": self.form, "url": self.url,
            "periodEnd": self.period_end.isoformat(),
            "fyCur": f"FY{self.period_end.year}", "fyPrior": f"FY{self.period_end.year - 1}",
            "rows": self.rows, "derived": self.derived,
            "textFigures": self.text_figures, "sections": self.sections,
        }


# --- fetching ----------------------------------------------------------------


def latest_filing_url(fetcher: Fetcher, ticker: str, form: str = "10-K") -> tuple[str, str]:
    """Returns (document URL, company name) of the latest filing of `form` for `ticker`."""
    resp = fetcher.get(TICKERS_URL)
    if not resp:
        raise RuntimeError("could not load SEC ticker list (check user_agent has a contact email)")
    match = next((r for r in json.loads(resp.text).values() if r["ticker"].upper() == ticker.upper()), None)
    if not match:
        raise RuntimeError(f"{ticker} is not in the SEC ticker list")
    cik = str(match["cik_str"]).zfill(10)
    resp = fetcher.get(SUBMISSIONS_URL.format(cik=cik))
    if not resp:
        raise RuntimeError(f"could not load SEC filing index for {ticker}")
    recent = json.loads(resp.text)["filings"]["recent"]
    for i, kind in enumerate(recent["form"]):
        if kind == form:
            url = ARCHIVE_URL.format(
                cik=int(cik), accession=recent["accessionNumber"][i].replace("-", ""), document=recent["primaryDocument"][i]
            )
            return url, match["title"]
    raise RuntimeError(f"no {form} found among {ticker}'s recent filings")


# --- parsing -----------------------------------------------------------------


def _number(tag: Tag) -> float | None:
    text = tag.get_text(strip=True)
    fmt = (tag.get("format") or "").lower()
    if "zero" in fmt or text in {"", "-", "—", "–"}:
        value = 0.0
    else:
        if "comma-decimal" in fmt or "numcommadecimal" in fmt:
            text = text.replace(".", "").replace(",", ".")
        digits = re.sub(r"[^\d.]", "", text.replace(",", ""))
        try:
            value = float(digits)
        except ValueError:
            return None
    value *= 10 ** int(tag.get("scale") or 0)
    return -value if tag.get("sign") == "-" else value


def _contexts(soup: BeautifulSoup) -> dict[str, Period]:
    """Context id -> period, keeping only contexts without dimensions (whole-company figures)."""
    out = {}
    for ctx in soup.find_all(lambda t: _local(t.name) == "context"):
        if ctx.find(lambda t: _local(t.name) == "segment"):
            continue
        dates = {_local(t.name): t.get_text(strip=True) for t in ctx.find_all(lambda t: _local(t.name) in {"startdate", "enddate", "instant"})}
        try:
            if "instant" in dates:
                out[ctx["id"]] = Period(None, date.fromisoformat(dates["instant"]))
            else:
                out[ctx["id"]] = Period(date.fromisoformat(dates["startdate"]), date.fromisoformat(dates["enddate"]))
        except (KeyError, ValueError):
            continue
    return out


def _near(a: date, b: date, days: int = 10) -> bool:
    return abs((a - b).days) <= days


def _fmt_money(value: float) -> str:
    sign = "-" if value < 0 else ""
    value = abs(value)
    for unit, size in (("T", 1e12), ("B", 1e9), ("M", 1e6)):
        if value >= size:
            return f"{sign}${value / size:,.1f}{unit}"
    return f"{sign}${value:,.0f}"


def _derive(rows: list[dict]) -> list[dict]:
    get = {r["label"]: r for r in rows}

    def val(label: str, period: str) -> float | None:
        cell = get.get(label, {}).get(period)
        return cell["value"] if cell else None

    out = []

    def pct(label: str, num: float | None, den: float | None) -> None:
        if num is not None and den:
            out.append({"label": label, "text": f"{num / den * 100:.1f}%"})

    def growth(label: str, row: str) -> None:
        cur, prior = val(row, "cur"), val(row, "prior")
        if cur is not None and prior:
            out.append({"label": label, "text": f"{(cur / prior - 1) * 100:+.1f}%"})

    growth("Revenue growth (YoY)", "Revenue")
    pct("Gross margin", val("Gross profit", "cur"), val("Revenue", "cur"))
    pct("Operating margin", val("Operating income", "cur"), val("Revenue", "cur"))
    pct("Net margin", val("Net income", "cur"), val("Revenue", "cur"))
    growth("Net income growth (YoY)", "Net income")
    growth("Diluted EPS growth (YoY)", "EPS (diluted)")
    ocf, capex = val("Operating cash flow", "cur"), val("Capital expenditures", "cur")
    if ocf is not None and capex is not None:
        fcf = ocf - abs(capex)
        out.append({"label": "Free cash flow", "text": _fmt_money(fcf)})
        pct("FCF margin", fcf, val("Revenue", "cur"))
    ca, cl = val("Total current assets", "cur"), val("Total current liabilities", "cur")
    if ca is not None and cl:
        out.append({"label": "Current ratio", "text": f"{ca / cl:.2f}x"})
    cash = sum(v for v in (val("Cash and equivalents", "cur"), val("Short-term investments", "cur")) if v)
    if cash:
        out.append({"label": "Cash + short-term investments", "text": _fmt_money(cash)})
    returned = sum(abs(v) for v in (val("Share buybacks", "cur"), val("Dividends paid", "cur")) if v)
    if returned:
        out.append({"label": "Returned to shareholders", "text": _fmt_money(returned)})
    return out


def _sanitize(soup: BeautifulSoup, base_url: str) -> str:
    for hidden in soup.find_all(lambda t: _local(t.name) == "header" and (t.name or "").startswith("ix")):
        hidden.decompose()
    for tag in soup.find_all(_UNSAFE_TAGS):
        tag.decompose()
    for tag in soup.find_all(True):
        for attr in list(tag.attrs):
            value = str(tag.attrs[attr]).strip().lower()
            if attr.lower().startswith("on") or value.startswith("javascript:"):
                del tag.attrs[attr]
        if tag.name == "img" and tag.get("src"):
            tag["src"] = urljoin(base_url, tag["src"])
        if tag.name == "a" and (tag.get("href") or "").startswith(("http", "//")):
            tag["target"], tag["rel"] = "_blank", "noopener"
    body = soup.body or soup
    return "".join(str(c) for c in body.contents)


def parse_filing(html: str, url: str = "", ticker: str = "", form: str = "10-K") -> Filing:
    # Filings are XHTML; the lenient HTML parser copes with SEC's occasional malformed markup.
    warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)
    try:
        soup = BeautifulSoup(html, "lxml")
    except Exception:  # lxml missing
        soup = BeautifulSoup(html, "html.parser")
    contexts = _contexts(soup)

    dei = {}
    for tag in soup.find_all(lambda t: _local(t.name) == "nonnumeric"):
        name = tag.get("name", "")
        if name.startswith("dei:") and name not in dei:
            dei[name] = tag
    period_tag = dei.get("dei:DocumentPeriodEndDate")
    current = contexts.get(period_tag.get("contextref")) if period_tag else None
    if not current:
        raise RuntimeError("not an inline-XBRL filing (no dei:DocumentPeriodEndDate context)")
    company = dei["dei:EntityRegistrantName"].get_text(" ", strip=True) if "dei:EntityRegistrantName" in dei else ticker
    if not ticker and "dei:TradingSymbol" in dei:
        ticker = dei["dei:TradingSymbol"].get_text(strip=True)
    prior_end = current.end - timedelta(days=365)

    def which(period: Period) -> str | None:
        if period.start is None:
            return "cur" if _near(period.end, current.end) else "prior" if _near(period.end, prior_end) else None
        if abs(period.days - current.days) > 15:  # e.g. a quarter inside an annual report
            return None
        return "cur" if _near(period.end, current.end) else "prior" if _near(period.end, prior_end) else None

    # One pass in document order: facts, page numbers, Item headings and dollar figures in prose.
    facts: dict[str, list[Fact]] = {}
    text_candidates: list[tuple[NavigableString, re.Match, int, str]] = []
    sections: list[tuple[str, str, Tag]] = []
    page, section, order = 1, "Cover", 0
    for node in list(soup.descendants):
        order += 1
        if isinstance(node, Tag):
            if _PAGE_BREAK.search(node.get("style") or ""):
                page += 1
            if _local(node.name) == "nonfraction" and node.get("contextref") in contexts:
                concept = node.get("name", "").split(":")[-1]
                value = _number(node)
                if value is not None:
                    fact = Fact(concept, value, contexts[node["contextref"]], node, node.find_parent("table") is not None, order)
                    facts.setdefault(concept, []).append(fact)
                    node["data-page"], node["data-section"] = str(page), section
            continue
        if not isinstance(node, NavigableString) or not node.strip():
            continue
        text = str(node)
        if (m := _ITEM_HEADING.match(text)) and node.parent is not None and len(node.parent.get_text(strip=True)) < 250:
            if node.find_parent("table") is None or m.group(2).strip():
                section = f"Item {m.group(1).upper()}"
                sections.append((section, _title(m.group(2)), node.parent))
        if node.find_parent("table") is None:
            for m in _TEXT_FIGURE.finditer(text):
                text_candidates.append((node, m, page, section))

    # Pick each row's figure: first occurrence, preferring the financial statement tables.
    rows, uid = [], 0
    for sec, label, kind, concepts in ROWS:
        row = {"section": sec, "label": label, "kind": kind}
        for concept in concepts:
            for period_key in ("cur", "prior"):
                if period_key in row:
                    continue
                matches = [f for f in facts.get(concept, []) if which(f.period) == period_key]
                if not matches:
                    continue
                best = min(matches, key=lambda f: (not f.in_table, f.order))
                uid += 1
                best.tag["id"] = best.tag.get("id") or f"sp-{uid}"
                best.tag["data-spider"] = "stat"
                row[period_key] = {
                    "value": best.value, "el": best.tag["id"],
                    "page": int(best.tag.get("data-page", 0)), "concept": concept,
                }
            if "cur" in row:
                break
        if "cur" in row or "prior" in row:
            rows.append(row)

    # Dollar amounts in the prose, spread evenly through the document.
    step = max(1, len(text_candidates) // MAX_TEXT_FIGURES)
    chosen = text_candidates[::step][:MAX_TEXT_FIGURES]
    by_node: dict[int, list] = {}
    for cand in chosen:
        by_node.setdefault(id(cand[0]), []).append(cand)
    text_figures = []
    for cands in by_node.values():
        node = cands[0][0]
        text, pos, pieces = str(node), 0, []
        for _, m, pg, sec in cands:
            uid += 1
            span = soup.new_tag("span", attrs={"id": f"sp-{uid}", "data-spider": "text"})
            span.string = m.group(0)
            pieces += [NavigableString(text[pos : m.start()]), span]
            pos = m.end()
            sentence = re.split(r"(?<=[.;])\s+", text[max(0, m.start() - 160) : m.end() + 160].strip())
            context = next((s for s in sentence if m.group(0) in s), m.group(0))
            text_figures.append({"el": f"sp-{uid}", "text": m.group(0), "context": context[:220], "page": pg, "section": sec})
        pieces.append(NavigableString(text[pos:]))
        for piece in pieces:
            node.insert_before(piece)
        node.extract()

    # Keep each Item's last heading: the first ones are usually the table of contents.
    last: dict[str, tuple[str, Tag]] = {}
    for name, title, tag in sections:
        last[name] = (title, tag)
    section_list = []
    for i, (name, (title, tag)) in enumerate(last.items()):
        tag["id"] = tag.get("id") or f"sp-sec-{i}"
        section_list.append({"name": name, "title": title, "el": tag["id"]})

    filing = Filing(
        company=company, ticker=ticker.upper(), form=form, period_end=current.end, url=url,
        rows=rows, derived=_derive(rows), text_figures=text_figures, sections=section_list,
    )
    filing.html = _sanitize(soup, url)
    return filing
