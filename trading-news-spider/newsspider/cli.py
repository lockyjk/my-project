"""Command line: crawl once, watch continuously, or query what has been collected."""

from __future__ import annotations

import argparse
import csv
import json
import logging
import re
import sys
import time
from datetime import timedelta

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
