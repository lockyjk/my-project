# Trading news spider

Crawls financial news, press releases, SEC filings and (optionally) Reddit, ranks every story by how likely it is to move a stock **right now**, and can send an animated spider through any company's 10-K. It's built for day trading: fresh, high-impact, ticker-specific news comes first.

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

## The filing spider 🕷️

`newsspider filing <TICKER>` downloads a company's latest 10-K (or `--form 10-Q`) from SEC EDGAR and builds a self-contained HTML page where an animated spider crawls the real filing:

- It walks down the document and boxes every key figure as it reads it, then draws pink and yellow threads to what it found and flashes the value.
- The report panel fills in live: income statement, balance sheet and cash flow (current vs prior year), "Spider's take" ratios (growth, margins, free cash flow, current ratio, cash returned to shareholders), the Items it has read, and dollar amounts from the text with their page numbers.
- The figures come from the filing's inline XBRL tags, so they are exact and the spider knows where each one sits on the page. Segment-only and quarterly figures are ignored.

```bash
newsspider filing MSFT --open
newsspider filing NVDA --caption "Wall Street's newest analyst is a spider 🕷️" -o nvda.html
newsspider filing --file saved-10k.htm      # a filing you already downloaded
```

Page controls: pause/play (space), ½× to 4× speed (`+`/`-`), replay (`r`). URL options:
- `?phone`: locks a 9:16 frame for screen-recording Shorts or TikToks.
- `?clean`: hides the controls.
- `?speed=2`: starts at that speed.

The SEC needs a real contact email in `user_agent` (see `config.toml`).

## The trading bot

`newsspider bot` day-trades the news the spider collects, following one written plan: **Catalyst Momentum**. The full rules are in `newsspider/strategy.py`, and every number is in `config.toml` under `[bot]` and `[risk]`.

**The plan, in short.** It only buys (no short selling) and never holds overnight.

1. **News:** since the last close, the stock had a positive story about earnings, guidance, an FDA decision, a contract, an analyst upgrade or a buyback. Stocks with dilution, bankruptcy, short-seller, legal or halt news are skipped for the day. So are merger targets, because they stick near the deal price.
2. **Stock is "in play":**
   - it opened at least 2% above yesterday's close (the gap);
   - it is trading at least 2× its normal volume for that time of day;
   - the price is $5 or more;
   - it trades at least $20M a day on average.
3. **Entry:** between 9:45 and 11:30 ET, a 1-minute bar closes above the first 15 minutes' high (the opening range) and above VWAP (the volume-weighted average price), but no more than 1% above that high, so it doesn't chase.
4. **Exit:**
   - the stop goes under the opening-range low or VWAP, whichever is higher;
   - take profit at 2R (twice the amount risked);
   - move the stop to the entry price at +1R;
   - sell anything still open at 15:55.
5. **Risk:**
   - 0.5% of the account at risk per trade, and no position bigger than 25% of the account;
   - at most 3 positions open at once and 6 trades a day, with one entry per stock per day;
   - stop for the day after losing 1.5%.

It is built on two effects that have been studied: after good earnings or guidance surprises, stocks tend to keep drifting the same way (post-earnings-announcement drift), and opening-range breakouts have worked better on high-volume news stocks than on the average stock. **That is not proof that it will make money.** Effects like these weaken, costs and slippage eat small edges, and a plan can fit the past and still fail. That's why the bot is built around testing:

```bash
newsspider watch                     # leave running for a few weeks so the spider builds up news history
newsspider bot backtest --since 30d  # replay the plan over that news with real 1-minute bars
newsspider bot run                   # paper-trade live with a simulated $100k account
newsspider bot status                # paper P&L, open positions, recent decisions
```

- **Backtest:** replays every story in the database against the minute bars that followed it. Fills are pessimistic: entry at the next bar's open plus slippage, a stop that gaps fills at the worse price, and if the stop and the target both hit in the same minute the stop counts first. It reports win rate, average win and loss in R, expectancy, profit factor, return and maximum drawdown, and saves every trade to `bot_report.json`. Yahoo only keeps about 30 days of 1-minute bars, so backtest news soon after collecting it.
- **Paper trading** (the default): a local simulated account in `paper_account.json`. Every entry, skip and exit is logged with its reason in `bot_journal.jsonl`.
- **Alpaca:** `--broker alpaca` trades through [Alpaca](https://alpaca.markets) using your `ALPACA_API_KEY_ID` and `ALPACA_API_SECRET_KEY`. It uses Alpaca's paper account unless you add `--live`. Orders are brackets, so the stop and target sit on Alpaca's servers even if your computer goes off.
- **Live money is locked:** `--live` refuses to start unless the saved backtest has at least 30 trades, positive expectancy and a profit factor of at least 1.2. Then you must type `LIVE` to confirm. Paper-trade for a few weeks first and compare the results with the backtest. If they differ a lot, the backtest is too optimistic.

Notes: it uses Yahoo's free unofficial minute data for decisions, which can lag or stop working, so use a paid data feed for real money. The bot must be running during market hours. It doesn't know about market holidays unless you use Alpaca, which reports when the market is open. Nothing here is financial advice.

### 24/5 stocks (round-the-clock trading)

Some brokers trade US stocks from Sunday 20:00 to Friday 20:00 ET. Most catalysts arrive outside regular hours (earnings at 16:05 or 7:00, FDA decisions, 8-K filings), so there's a second plan built for that, **24/5 News Reaction** (`newsspider/strategy24.py`, settings in `[bot24]`):

```bash
newsspider bot backtest --plan 24h --since 30d
```

- **Anchor:** the moment the story came out, not the 9:30 open. The starting price is the last price before the story, and the reaction range is the first 15 minutes after it.
- **Entry:** up 2%+ from that starting price, 3×+ normal volume for that time of day, $250k+ traded since the story, and a breakout above the reaction range and above VWAP measured from the story. It must enter within 2 hours.
- **Exit:** 2R target, breakeven at +1R, held no longer than 4 hours, and always sold before the Friday 20:00 close.
- **Costs:** 0.15% slippage per side, three times the regular-hours plan, because spreads are wider at night.
- **News rules:** the same buy and veto catalysts as the regular plan. A veto story within 12 hours cancels the trade, each stock trades at most once per 24 hours, and weekend news waits for the Sunday 20:00 open.
- **Report:** trades and P&L split by session (overnight, pre-market, regular, after-hours), so you can see where the edge is, if there is one.

**Data limit:** Yahoo's free minute bars cover pre-market (4:00–9:30) and after-hours (16:00–20:00), but **not the overnight session (20:00–4:00)**. Stories that break overnight are judged on the next pre-market bars, so a backtest can't show overnight entries. Testing true overnight trading needs a data feed that includes the overnight session. Live trading in those hours also needs a broker that supports it, and extended-hours orders usually have to be limit orders.

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
