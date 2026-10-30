# Trading news spider

Crawls financial news, press releases, SEC filings and (optionally) Reddit, then ranks every story by how likely it is to move a stock **right now**. It's built for day trading: fresh, high-impact, ticker-specific news comes first.

## What it does

1. **Crawls** about 16 sources (see `config.toml`). Per-ticker feeds run once for each watchlist symbol:
   - Yahoo Finance, Google News and Nasdaq ticker feeds
   - CNBC (top, markets, earnings), MarketWatch, Seeking Alpha Market Currents, Nasdaq Markets
   - PR Newswire and GlobeNewswire press releases, where most small-cap catalysts break first
   - SEC EDGAR live 8-K and 424B (offering) filings, with each filer's CIK resolved to its ticker
   - Federal Reserve press releases
   - r/wallstreetbets and r/stocks (off by default)
2. **Is polite:** it obeys robots.txt, waits between hits to the same host, sends `ETag`/`If-Modified-Since` so unchanged feeds cost nothing, and backs off on 429/5xx responses.
3. **Enriches** each story:
   - **Tickers:** from `$CASHTAGS`, `(NASDAQ: XYZ)` style tags, company-name aliases and watchlist symbols.
   - **Catalysts:** halt, FDA, merger, bankruptcy, earnings, guidance, offering/dilution, short report, analyst rating, legal, contract, buyback, insider, split, leadership, macro, SEC filing. Each has a weight for how hard it usually moves a stock.
   - **Sentiment:** a finance-specific word list that handles negation ("did not beat" counts as negative).
   - **Score:** catalyst weight × sentiment strength, with a boost for watchlist tickers. It halves every `half_life_minutes`, so old news sinks.
4. **De-duplicates** by cleaned-up URL and by headline fingerprint. When the same story shows up on several outlets it is stored once, and each extra outlet raises its score.
5. **Stores** everything in SQLite (`news.db`) so you can query, rank and export.

## Setup

```bash
cd trading-news-spider
pip install -e .            # or: pip install -r requirements.txt
```

Edit `config.toml`:
- `user_agent`: **put your real email in it.** SEC EDGAR blocks requests without a contact address.
- `watchlist` / `aliases`: the tickers you trade.
- `alerts.webhook_url`: optional Discord or Slack webhook for push alerts.

## Use

```bash
newsspider run                         # crawl once, print new stories best-first
newsspider watch                       # crawl every 60s, alert on score >= alerts.min_score
newsspider top --since 2h              # highest-impact stories in the last 2 hours
newsspider top --ticker NVDA --since 1d
newsspider heat --since 4h --quotes    # tickers ranked by news impact, with live % change
newsspider export --since 1d -o today.csv
newsspider export --format json --ticker TSLA
```

(Without installing, use `python -m newsspider ...` from this folder.)

Output line format:

```
▲  12.40   5m  $NVDA  [earnings,guidance] Nvidia beats estimates, raises guidance ...  (CNBC Earnings)
```

The arrow shows sentiment, then the score, the story's age, tickers, catalyst tags, headline and source.

## Adding sources

Add a `[[sources]]` block to `config.toml` with `kind = "rss"`, `"sec"` or `"reddit"`. Put `{ticker}` in the URL and set `per_ticker = true` to run it for every watchlist symbol.

## Notes and limits

- It reads headlines and summaries from public feeds, not full article pages behind paywalls. Respect each site's terms of use. Don't lower `min_host_interval` aggressively.
- `heat --quotes` uses Yahoo's unofficial chart endpoint. It can change or rate-limit you without notice.
- Scores are a triage aid, not trading signals. Always read the source before you trade.

## Tests

```bash
pip install pytest && pytest
```

The tests run fully offline against sample feeds in `tests/fixtures` and a local HTTP server.
