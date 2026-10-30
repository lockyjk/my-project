"""Generates sample_10k.htm: a fictional company's 10-K in inline XBRL, for tests and demos.

Run: python tests/fixtures/build_sample_10k.py
"""

from pathlib import Path

CUR, PRI = "FY2026", "FY2025"
CONTEXTS = {
    "D2026": ("2025-07-01", "2026-06-30"),
    "D2025": ("2024-07-01", "2025-06-30"),
    "I2026": ("2026-06-30",),
    "I2025": ("2025-06-30",),
    "Q4": ("2026-04-01", "2026-06-30"),  # a quarter: must not be mistaken for the year
}


def ctx_xml() -> str:
    out = []
    for cid, period in CONTEXTS.items():
        p = (f"<xbrli:instant>{period[0]}</xbrli:instant>" if len(period) == 1
             else f"<xbrli:startDate>{period[0]}</xbrli:startDate><xbrli:endDate>{period[1]}</xbrli:endDate>")
        out.append(f'<xbrli:context id="{cid}"><xbrli:entity><xbrli:identifier scheme="http://www.sec.gov/CIK">0000000001</xbrli:identifier></xbrli:entity><xbrli:period>{p}</xbrli:period></xbrli:context>')
    # Segment context: a single division's revenue. Must be ignored.
    out.append('<xbrli:context id="SEG"><xbrli:entity><xbrli:identifier scheme="http://www.sec.gov/CIK">0000000001</xbrli:identifier>'
               '<xbrli:segment><xbrldi:explicitMember dimension="us-gaap:StatementBusinessSegmentsAxis">exmp:CloudMember</xbrldi:explicitMember></xbrli:segment>'
               '</xbrli:entity><xbrli:period><xbrli:startDate>2025-07-01</xbrli:startDate><xbrli:endDate>2026-06-30</xbrli:endDate></xbrli:period></xbrli:context>')
    return "".join(out)


def nf(concept: str, ctx: str, value: float, scale: int = 6, decimals: str = "-6") -> str:
    """Inline XBRL number; negative values shown in parentheses with sign='-'."""
    shown = f"{abs(value):,.2f}" if scale == 0 else f"{abs(value) / 10**scale:,.0f}"
    sign = ' sign="-"' if value < 0 else ""
    tag = (f'<ix:nonFraction name="us-gaap:{concept}" contextRef="{ctx}" unitRef="usd" decimals="{decimals}" '
           f'scale="{scale}" format="ixt:num-dot-decimal"{sign}>{shown}</ix:nonFraction>')
    return f"({tag})" if value < 0 else tag


def table(title: str, rows: list, instant: bool = False, outflow: set = frozenset()) -> str:
    c, p = ("I2026", "I2025") if instant else ("D2026", "D2025")
    body = []
    for row in rows:
        if isinstance(row, str):
            body.append(f'<tr><td colspan="3" style="padding-top:8px;font-weight:bold">{row}</td></tr>')
            continue
        label, concept, cur, pri, *opt = row
        scale = opt[0] if opt else 6
        bold = "font-weight:bold;border-top:1px solid #000" if label.startswith("Total") or label in {"Net income", "Gross margin", "Operating income"} else ""

        def cell(ctx, v):
            if concept in outflow:  # payments are tagged positive but shown in parentheses
                return "(" + nf(concept, ctx, v, scale) + ")"
            return nf(concept, ctx, v, scale, "2" if scale == 0 else "-6")

        body.append(f'<tr style="{bold}"><td style="padding:2px 4px">{label}</td>'
                    f'<td style="text-align:right;padding:2px 8px">$ {cell(c, cur)}</td>'
                    f'<td style="text-align:right;padding:2px 8px">$ {cell(p, pri)}</td></tr>')
    return (f'<p style="text-align:center;font-weight:bold;margin-top:18px">{title}</p>'
            f'<p style="font-size:9pt">(In millions, except per share amounts)</p>'
            f'<table style="width:100%;border-collapse:collapse;font-size:10pt">'
            f'<tr style="font-weight:bold;border-bottom:1px solid #000"><td>Year Ended June 30,</td>'
            f'<td style="text-align:right">2026</td><td style="text-align:right">2025</td></tr>{"".join(body)}</table>')


PAGE = '<p style="text-align:center;font-size:9pt;margin-top:24px">{n}</p><hr style="page-break-after:always"/>'

LOREM = ("The Company designs, develops and sells software and devices to consumers and businesses worldwide. "
         "Our results depend on demand for our products, the pace of technology change, and economic conditions in the markets we serve. ")


def build() -> str:
    income = table("INCOME STATEMENTS", [
        ("Revenue", "RevenueFromContractWithCustomerExcludingAssessedTax", 48210e6, 41355e6),
        ("Cost of revenue", "CostOfRevenue", 19870e6, 17602e6),
        ("Gross margin", "GrossProfit", 28340e6, 23753e6),
        ("Research and development", "ResearchAndDevelopmentExpense", 6120e6, 5480e6),
        ("Sales and marketing", "SellingAndMarketingExpense", 4905e6, 4610e6),
        ("General and administrative", "GeneralAndAdministrativeExpense", 1830e6, 1702e6),
        ("Operating income", "OperatingIncomeLoss", 15485e6, 11961e6),
        ("Other income (expense), net", "NonoperatingIncomeExpense", 412e6, -188e6),
        ("Income before income taxes", "IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest", 15897e6, 11773e6),
        ("Provision for income taxes", "IncomeTaxExpenseBenefit", 2861e6, 2237e6),
        ("Net income", "NetIncomeLoss", 13036e6, 9536e6),
        "Earnings per share:",
        ("Basic", "EarningsPerShareBasic", 5.21, 3.79, 0),
        ("Diluted", "EarningsPerShareDiluted", 5.15, 3.75, 0),
        "Weighted average shares outstanding:",
        ("Basic", "WeightedAverageNumberOfSharesOutstandingBasic", 2502e6, 2516e6),
        ("Diluted", "WeightedAverageNumberOfDilutedSharesOutstanding", 2531e6, 2543e6),
    ])
    balance = table("BALANCE SHEETS", [
        "Current assets:",
        ("Cash and cash equivalents", "CashAndCashEquivalentsAtCarryingValue", 9412e6, 7288e6),
        ("Short-term investments", "ShortTermInvestments", 14775e6, 13120e6),
        ("Accounts receivable, net", "AccountsReceivableNetCurrent", 8904e6, 7615e6),
        ("Inventories", "InventoryNet", 1233e6, 1410e6),
        ("Other current assets", "OtherAssetsCurrent", 2145e6, 1960e6),
        ("Total current assets", "AssetsCurrent", 36469e6, 31393e6),
        ("Property and equipment, net", "PropertyPlantAndEquipmentNet", 22870e6, 18455e6),
        ("Goodwill", "Goodwill", 11240e6, 11050e6),
        ("Other long-term assets", "OtherAssetsNoncurrent", 6180e6, 5902e6),
        ("Total assets", "Assets", 76759e6, 66800e6),
        "Current liabilities:",
        ("Accounts payable", "AccountsPayableCurrent", 3980e6, 3412e6),
        ("Current portion of long-term debt", "LongTermDebtCurrent", 1250e6, 1000e6),
        ("Accrued compensation", "EmployeeRelatedLiabilitiesCurrent", 4610e6, 4128e6),
        ("Total current liabilities", "LiabilitiesCurrent", 9840e6, 8540e6),
        ("Long-term debt", "LongTermDebtNoncurrent", 14300e6, 15550e6),
        ("Other long-term liabilities", "OtherLiabilitiesNoncurrent", 5120e6, 4870e6),
        ("Total liabilities", "Liabilities", 29260e6, 28960e6),
        ("Total stockholders' equity", "StockholdersEquity", 47499e6, 37840e6),
    ], instant=True)
    cash = table("CASH FLOWS STATEMENTS", [
        "Operations",
        ("Net income", "NetIncomeLoss", 13036e6, 9536e6),
        ("Depreciation and amortization", "DepreciationDepletionAndAmortization", 3410e6, 2980e6),
        ("Stock-based compensation expense", "ShareBasedCompensation", 1980e6, 1750e6),
        ("Net cash from operations", "NetCashProvidedByUsedInOperatingActivities", 17920e6, 14105e6),
        "Investing",
        ("Additions to property and equipment", "PaymentsToAcquirePropertyPlantAndEquipment", 7850e6, 6320e6),
        ("Net cash used in investing", "NetCashProvidedByUsedInInvestingActivities", -9470e6, -8115e6),
        "Financing",
        ("Common stock repurchased", "PaymentsForRepurchaseOfCommonStock", 4200e6, 3600e6),
        ("Common stock cash dividends paid", "PaymentsOfDividendsCommonStock", 2250e6, 2010e6),
        ("Net cash used in financing", "NetCashProvidedByUsedInFinancingActivities", -6326e6, -5010e6),
    ], outflow={"PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsForRepurchaseOfCommonStock", "PaymentsOfDividendsCommonStock"})

    def item(num, title, paras):
        return f'<p style="font-weight:bold;margin-top:20px">Item {num}. {title}</p>' + "".join(f"<p>{p}</p>" for p in paras)

    toc = "".join(f'<tr><td><a href="#i{n}">Item {n}.</a></td><td>{t}</td></tr>' for n, t in
                  [("1", "Business"), ("1A", "Risk Factors"), ("3", "Legal Proceedings"), ("7", "Management's Discussion and Analysis"),
                   ("7A", "Quantitative and Qualitative Disclosures About Market Risk"), ("8", "Financial Statements and Supplementary Data")])

    pages = [
        f'''<p style="text-align:center;font-weight:bold;font-size:14pt">UNITED STATES SECURITIES AND EXCHANGE COMMISSION</p>
<p style="text-align:center">Washington, D.C. 20549</p><p style="text-align:center;font-weight:bold;font-size:16pt">FORM 10-K</p>
<p style="text-align:center">For the fiscal year ended <ix:nonNumeric name="dei:DocumentPeriodEndDate" contextRef="D2026">June 30, 2026</ix:nonNumeric></p>
<p style="text-align:center;font-weight:bold;font-size:15pt"><ix:nonNumeric name="dei:EntityRegistrantName" contextRef="D2026">EXAMPLE CORP</ix:nonNumeric></p>
<p style="text-align:center">Trading symbol: <ix:nonNumeric name="dei:TradingSymbol" contextRef="D2026">EXMP</ix:nonNumeric> &middot; Fictional company, sample data for testing</p>
<p style="font-weight:bold;margin-top:30px">TABLE OF CONTENTS</p><table style="width:100%">{toc}</table>
<script>alert("this must be stripped")</script>''',
        item("1", "Business", [LOREM * 3, "We employ approximately 61,000 people. Cloud revenue, which is reported in our Cloud segment, was "
             + '<ix:nonFraction name="us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax" contextRef="SEG" unitRef="usd" decimals="-6" scale="6" format="ixt:num-dot-decimal">21,400</ix:nonFraction>'
             + " million this year.", LOREM * 2]),
        item("1A", "Risk Factors", [
            "Our global operations expose us to currency risk. A 10% decline in foreign exchange rates would reduce revenue by approximately $2.6 billion.",
            LOREM * 2,
            "We have committed to purchase $16.0 billion of data-center capacity over the next five years, and those commitments may exceed demand.",
            "Cybersecurity incidents could cost us significantly; in fiscal year 2026 we spent $412 million on security programs.",
            LOREM * 2]),
        item("3", "Legal Proceedings", ["We are party to antitrust litigation in several jurisdictions. We accrued $1.1 billion for these matters, which we believe is adequate.", LOREM]),
        item("7", "Management's Discussion and Analysis of Financial Condition and Results of Operations", [
            "Revenue increased $6.9 billion or 17% driven by growth in cloud services. Fourth quarter revenue was "
            + '<ix:nonFraction name="us-gaap:RevenueFromContractWithCustomerExcludingAssessedTax" contextRef="Q4" unitRef="usd" decimals="-6" scale="6" format="ixt:num-dot-decimal">13,050</ix:nonFraction> million.',
            "Gross margin increased $4.6 billion or 19%. Operating income increased $3.5 billion or 29%.",
            LOREM * 2,
            "Research and development expenses increased $640 million or 12%, driven by investments in AI infrastructure.",
            "Cash from operations increased $3.8 billion to $17.9 billion. We returned $6.5 billion to shareholders through buybacks and dividends.",
            LOREM]),
        item("7A", "Quantitative and Qualitative Disclosures About Market Risk", [
            "A 100 basis point increase in interest rates would decrease the fair value of our fixed-income portfolio by $1.2 billion.", LOREM * 2]),
        item("8", "Financial Statements and Supplementary Data", ["The following consolidated statements are presented in millions."]) + income,
        balance,
        cash,
    ]
    body = "".join(p + PAGE.format(n=i + 1) for i, p in enumerate(pages))
    return f'''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:ix="http://www.xbrl.org/2013/inlineXBRL" xmlns:xbrli="http://www.xbrl.org/2003/instance"
 xmlns:us-gaap="http://fasb.org/us-gaap/2025" xmlns:dei="http://xbrl.sec.gov/dei/2025" xmlns:xbrldi="http://xbrl.org/2006/xbrldi">
<head><title>exmp-20260630</title></head>
<body style="font-family:'Times New Roman';font-size:10pt">
<div style="display:none"><ix:header><ix:resources>{ctx_xml()}</ix:resources></ix:header></div>
{body}
</body></html>'''


if __name__ == "__main__":
    out = Path(__file__).with_name("sample_10k.htm")
    out.write_text(build())
    print(f"wrote {out}")
