"""Command line: crawl once, watch continuously, or query what has been collected."""

from __future__ import annotations

import argparse
import csv
import json
import logging
import re
import sys
import time
import webbrowser
from datetime import timedelta
from pathlib import Path

from .alerts import alert, format_line
from .quotes import get_quotes
from .spider import Config, Spider


def duration(text: str) -> timedelta:
    m = re.fullmatch(r"(\d+)([mhd])", text)
    if not m:
        raise argparse.ArgumentTypeError("use e.g. 30m, 4h or 2d")
    return timedelta(**{{"m": "minutes", "h": "hours", "d": "days"}[m.group(2)]: int(m.group(1))})


def cmd_run(spider: Spider, args) -> None:
    fresh = spider.crawl()
    print(f"{len(fresh)} new stories")
    for art in fresh[: args.limit]:
        print(format_line(art))
    alert(fresh, spider.config.alerts.get("min_score", 6.0), spider.config.alerts.get("webhook_url", ""))


def cmd_watch(spider: Spider, args) -> None:
    interval = args.interval or spider.config.poll_seconds
    min_score = spider.config.alerts.get("min_score", 6.0)
    print(f"watching {len(spider.config.targets())} feeds every {interval}s; alerting at score >= {min_score}")
    first = True
    while True:
        started = time.monotonic()
        fresh = spider.crawl()
        # The first pass backfills the last day of news; only alert on what arrives after.
        if not first:
            alert(fresh, min_score, spider.config.alerts.get("webhook_url", ""))
        else:
            print(f"backfilled {len(fresh)} stories; now listening for new ones")
        first = False
        time.sleep(max(5, interval - (time.monotonic() - started)))


def cmd_top(spider: Spider, args) -> None:
    for item in spider.store.recent(args.since, ticker=args.ticker, limit=args.limit):
        print(format_line(item))


def cmd_heat(spider: Spider, args) -> None:
    heat = spider.store.ticker_heat(args.since, limit=args.limit)
    quotes = get_quotes(spider.fetcher, [h["ticker"] for h in heat]) if args.quotes else {}
    print(f"{'ticker':<8}{'score':>8}{'stories':>9}{'sent':>7}{'chg%':>8}  catalysts")
    for h in heat:
        q = quotes.get(h["ticker"])
        chg = f"{q.change_pct:+.2f}" if q else "-"
        print(f"{h['ticker']:<8}{h['score']:>8.2f}{h['stories']:>9}{h['sentiment']:>7.2f}{chg:>8}  {', '.join(h['catalysts'])}")


def cmd_export(spider: Spider, args) -> None:
    items = spider.store.recent(args.since, ticker=args.ticker, limit=args.limit)
    out = open(args.output, "w", newline="") if args.output else sys.stdout
    if args.format == "json":
        json.dump(items, out, indent=2)
    else:
        writer = csv.DictWriter(out, fieldnames=list(items[0]) if items else ["title"])
        writer.writeheader()
        for item in items:
            writer.writerow({k: ";".join(v) if isinstance(v, list) else v for k, v in item.items()})
    if args.output:
        out.close()
        print(f"wrote {len(items)} stories to {args.output}")


def cmd_filing(spider: Spider, args) -> None:
    from .filing import latest_filing_url, parse_filing
    from .report import render

    if args.file:
        url, html = args.file, Path(args.file).read_text(errors="replace")
    else:
        if "example.com" in spider.config.user_agent:
            print("warning: set a real contact email in config.toml user_agent; SEC rejects anonymous requests", file=sys.stderr)
        url, company = latest_filing_url(spider.fetcher, args.ticker, args.form)
        print(f"reading {company} {args.form}: {url}")
        resp = spider.fetcher.get(url)
        if not resp:
            sys.exit(f"could not download {url}")
        html = resp.text
    filing = parse_filing(html, url=url, ticker="" if args.file else args.ticker, form=args.form)
    out = Path(args.output or f"{filing.ticker or 'filing'}-{args.form}-spider.html".lower())
    out.write_text(render(filing, caption=args.caption, brand=args.brand))
    print(f"{len(filing.rows)} statement figures, {len(filing.text_figures)} figures in text -> {out}")
    if args.open:
        webbrowser.open(out.resolve().as_uri())


def _bot_parts(spider: Spider):
    from .risk import RiskRules
    from .strategy import Plan

    return Plan.from_config(spider.config.bot), RiskRules.from_config(spider.config.risk)


def cmd_bot_backtest(spider: Spider, args) -> None:
    from .backtest import default_loader, passes_live_gate, run_backtest

    plan, rules = _bot_parts(spider)
    articles = spider.store.recent(args.since, limit=1_000_000)
    span = f"{args.since.days}d" if args.since.days else f"{args.since.seconds // 3600}h"
    if args.plan == "24h":
        from .strategy24 import Plan24, by_session_stats, default_loader_24, run_backtest_24

        print(f"replaying {len(articles)} stories from the last {span} with the 24/5 News Reaction plan (extended-hours bars)...")
        report = run_backtest_24(Plan24.from_config(spider.config.bot24), rules, articles, default_loader_24(spider.fetcher), equity=args.equity)
    else:
        print(f"replaying {len(articles)} stories from the last {span} with the regular-hours Catalyst Momentum plan...")
        report = run_backtest(plan, rules, articles, default_loader(spider.fetcher), equity=args.equity)
    for t in report.trades:
        print(f"{t.day} {t.entry_time:%H:%M} {t.ticker:<6} {t.qty:>5} @ {t.entry:<9.2f} -> {t.exit:<9.2f} {t.r:+.2f}R {t.pnl:>+10.2f}  {t.exit_reason:<14} {t.news[:60]}")
    if args.verbose:
        for ticker, day, why in report.skipped:
            print(f"  skipped {day} {ticker}: {why}")
    print()
    for key, value in report.stats.items():
        print(f"  {key.replace('_', ' '):<18} {value}")
    if args.plan == "24h" and report.trades:
        print("\n  by session          trades  wins  total R       P&L")
        for name, st in by_session_stats(report.trades).items():
            print(f"  {name:<18} {st['trades']:>7} {st['wins']:>5} {st['total_r']:>+8.2f} {st['pnl']:>+10.2f}")
    ok, verdict = passes_live_gate(report.stats, spider.config.bot.get("live_min_trades", 30), spider.config.bot.get("live_min_profit_factor", 1.2))
    print(f"\nlive-trading gate: {'PASS' if ok else 'NOT YET'}: {verdict}")
    Path(args.report).write_text(json.dumps(report.to_dict(), indent=2, default=str))
    print(f"full report saved to {args.report}")


def _make_broker(spider: Spider, args):
    from .broker import AlpacaBroker, PaperBroker

    if args.broker == "paper":
        if args.live:
            sys.exit("--live needs --broker alpaca")
        return PaperBroker(spider.config.bot.get("paper_account", "paper_account.json"), spider.config.bot.get("paper_cash", 100_000))
    if args.live:
        from .backtest import passes_live_gate

        if spider.config.bot.get("require_backtest_for_live", True):
            report = Path(args.report)
            if not report.exists():
                sys.exit(f"no backtest found at {report}; run `newsspider bot backtest` first")
            ok, verdict = passes_live_gate(json.loads(report.read_text())["stats"],
                                           spider.config.bot.get("live_min_trades", 30), spider.config.bot.get("live_min_profit_factor", 1.2))
            if not ok:
                sys.exit(f"refusing to trade real money: {verdict}")
        if input("This will place REAL orders with real money. Type LIVE to continue: ").strip() != "LIVE":
            sys.exit("cancelled")
    return AlpacaBroker(live=args.live)


def cmd_bot_run(spider: Spider, args) -> None:
    from .bars import fetch_bars
    from .broker import AlpacaBroker
    from .trader import Trader

    plan, rules = _bot_parts(spider)
    broker = _make_broker(spider, args)
    trader = Trader(
        plan, rules, broker,
        bars=lambda ticker: fetch_bars(spider.fetcher, ticker),
        news=lambda: spider.store.recent(timedelta(days=4), limit=1_000_000),
        journal=spider.config.bot.get("journal", "bot_journal.jsonl"),
    )
    market_open = (lambda: broker.clock()["is_open"]) if isinstance(broker, AlpacaBroker) else None
    trader.run(crawl=spider.crawl, poll_seconds=args.interval or spider.config.poll_seconds, market_open=market_open)


def cmd_bot_status(spider: Spider, args) -> None:
    from .broker import PaperBroker

    account = PaperBroker(spider.config.bot.get("paper_account", "paper_account.json"), spider.config.bot.get("paper_cash", 100_000))
    sells = [f for f in account.fills if f["side"] == "sell"]
    wins = sum(1 for f in sells if f["pnl"] > 0)
    print(f"paper equity ${account.equity():,.2f}  cash ${account.cash:,.2f}")
    print(f"closed trades {len(sells)}  wins {wins}  total P&L ${sum(f['pnl'] for f in sells):+,.2f}")
    for p in account.positions.values():
        print(f"  open {p.ticker} {p.qty} @ {p.entry:.2f} stop {p.stop:.2f} target {p.target:.2f}")
    journal = Path(spider.config.bot.get("journal", "bot_journal.jsonl"))
    if journal.exists():
        print("recent bot activity:")
        for line in journal.read_text().splitlines()[-15:]:
            e = json.loads(line)
            print(f"  {e['at'][:16]} {e['event']:<9} {e.get('ticker', '')} {e.get('reason', '')}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="newsspider", description="News scraper for day trading.")
    parser.add_argument("-c", "--config", default="config.toml")
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("run", help="crawl every source once and print new stories")
    p.add_argument("--limit", type=int, default=40)
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("watch", help="crawl forever and alert on high-impact news")
    p.add_argument("--interval", type=int, help="seconds between crawls (default from config)")
    p.set_defaults(func=cmd_watch)

    p = sub.add_parser("filing", help="animated spider that reads a company's latest 10-K/10-Q")
    p.add_argument("ticker", nargs="?", default="", help="e.g. MSFT")
    p.add_argument("--form", default="10-K", choices=["10-K", "10-Q", "20-F", "40-F"])
    p.add_argument("--file", help="read a filing saved on disk instead of downloading")
    p.add_argument("--caption", default="", help="big title text over the document (for recording)")
    p.add_argument("--brand", default="newsspider", help="name shown in the report header")
    p.add_argument("-o", "--output")
    p.add_argument("--open", action="store_true", help="open the result in your browser")
    p.set_defaults(func=cmd_filing)

    bot = sub.add_parser("bot", help="news-driven day-trading bot (paper by default)")
    bot_sub = bot.add_subparsers(dest="bot_command", required=True)
    p = bot_sub.add_parser("backtest", help="replay the trading plan over collected news")
    p.add_argument("--since", type=duration, default=timedelta(days=30))
    p.add_argument("--equity", type=float, default=100_000)
    p.add_argument("--report", default="bot_report.json")
    p.add_argument("--plan", choices=["regular", "24h"], default="regular",
                   help="regular-hours Catalyst Momentum, or 24/5 News Reaction for stocks traded around the clock")
    p.set_defaults(func=cmd_bot_backtest)
    p = bot_sub.add_parser("run", help="trade live news every minute during market hours")
    p.add_argument("--broker", choices=["paper", "alpaca"], default="paper")
    p.add_argument("--live", action="store_true", help="real money (Alpaca only, needs a passing backtest)")
    p.add_argument("--interval", type=int)
    p.add_argument("--report", default="bot_report.json")
    p.set_defaults(func=cmd_bot_run)
    p = bot_sub.add_parser("status", help="paper account, P&L and recent bot activity")
    p.set_defaults(func=cmd_bot_status)

    for name, func, help_text in [
        ("top", cmd_top, "highest-impact stories collected so far"),
        ("heat", cmd_heat, "tickers ranked by recent news impact"),
        ("export", cmd_export, "dump stories as CSV or JSON"),
    ]:
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--since", type=duration, default=timedelta(hours=6), help="e.g. 30m, 4h, 2d")
        p.add_argument("--limit", type=int, default=30 if name != "export" else 10_000)
        if name != "heat":
            p.add_argument("--ticker")
        if name == "heat":
            p.add_argument("--quotes", action="store_true", help="add live % change from Yahoo")
        if name == "export":
            p.add_argument("--format", choices=["csv", "json"], default="csv")
            p.add_argument("-o", "--output")
        p.set_defaults(func=func)

    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    try:
        args.func(Spider(Config.load(args.config)), args)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
