import json
from datetime import date, datetime, timedelta

import pytest

from newsspider.backtest import passes_live_gate, run_backtest, simulate_trade
from newsspider.bars import ET, Bar, by_session, parse_bars
from newsspider.broker import AlpacaBroker, PaperBroker
from newsspider.risk import RiskRules
from newsspider.strategy import Plan, Signal, check_entry, news_verdict, qualifying_news, session_for
from newsspider.trader import Trader

DAY = date(2026, 10, 28)  # a Wednesday
PLAN = Plan()


def session(day: date, closes: list[float], volume: float, start: float | None = None) -> list[Bar]:
    """Minute bars from 9:30 following `closes`, padded flat to 16:00."""
    closes = closes + [closes[-1]] * (390 - len(closes))
    bars, prev = [], start if start is not None else closes[0]
    t0 = datetime(day.year, day.month, day.day, 9, 30, tzinfo=ET)
    for i, c in enumerate(closes):
        o = prev
        bars.append(Bar(t0 + timedelta(minutes=i), o, max(o, c) + 0.05, min(o, c) - 0.05, c, volume))
        prev = c
    return bars


def history(days: int = 5) -> dict[date, list[Bar]]:
    out, d = {}, DAY
    while len(out) < days:
        d -= timedelta(days=1)
        if d.weekday() < 5:
            out[d] = session(d, [100.0], 1000)
    return out


def opening(gap_open: float = 104.0) -> list[float]:
    """15-minute opening range between ~104 and 105.5, a pause, then a breakout bar to 105.8."""
    rng = [gap_open, 105.0, 105.5, 104.5, 104.2, 105.2, 105.0, 104.6, 104.8, 105.3, 105.1, 104.9, 105.0, 105.2, 105.0]
    return rng + [105.0] * 5 + [105.8]


def scenario(after: list[float], gap_open: float = 104.0, volume: float = 3000) -> dict[date, list[Bar]]:
    days = history()
    days[DAY] = session(DAY, opening(gap_open) + after, volume, start=gap_open)
    return days


def calm_market(change: float = 0.2) -> dict[date, list[Bar]]:
    """SPY: flat history at 100, today drifting up `change` percent (or down if negative)."""
    days = history()
    days[DAY] = session(DAY, ramp(100.0, change / 390, 390), 50000, start=100.0)
    return days


def ramp(start: float, step: float, n: int) -> list[float]:
    return [round(start + step * (i + 1), 4) for i in range(n)]


def article(title="Acme beats estimates and raises guidance", cats=("earnings", "guidance"), sentiment=0.7,
            when=datetime(2026, 10, 28, 7, 0, tzinfo=ET), tickers=("ACME",)):
    return {"title": title, "catalysts": list(cats), "sentiment": sentiment, "tickers": list(tickers), "published": when.isoformat()}


# --- news rules --------------------------------------------------------------


def test_news_verdict():
    assert news_verdict(article(), PLAN)[0]
    assert not news_verdict(article(cats=("earnings", "offering")), PLAN)[0]
    assert not news_verdict(article(cats=("merger",)), PLAN)[0]
    assert not news_verdict(article(sentiment=-0.4), PLAN)[0]
    assert not news_verdict(article(cats=("macro",)), PLAN)[0]


def test_session_for_after_hours_and_weekend():
    assert session_for(datetime(2026, 10, 28, 8, 0, tzinfo=ET)) == date(2026, 10, 28)
    assert session_for(datetime(2026, 10, 28, 16, 30, tzinfo=ET)) == date(2026, 10, 29)
    assert session_for(datetime(2026, 10, 30, 17, 0, tzinfo=ET)) == date(2026, 11, 2)  # Friday evening -> Monday


def test_dilution_story_vetoes_the_ticker_that_day():
    good = article()
    bad = article(title="Acme prices $50M offering", cats=("offering",), sentiment=-0.3, when=datetime(2026, 10, 28, 8, 0, tzinfo=ET))
    assert ("ACME", DAY) in qualifying_news([good], PLAN)
    assert ("ACME", DAY) not in qualifying_news([good, bad], PLAN)


# --- entry rules ---------------------------------------------------------------


def entry_on(days, news_at=datetime(2026, 10, 28, 7, 0, tzinfo=ET)):
    today, hist = days[DAY], [b for d, b in sorted(days.items()) if d < DAY]
    for i in range(1, 120):
        sig, why = check_entry(PLAN, "ACME", today[:i], hist, news_at)
        if sig:
            return sig, i
    return None, why


def test_breakout_signal():
    sig, i = entry_on(scenario(ramp(105.8, 0.05, 60)))
    assert i == 21 and sig.entry == 105.8
    assert sig.stop < sig.entry and sig.target == pytest.approx(sig.entry + 2 * (sig.entry - sig.stop), abs=1e-3)
    assert "3.0x volume" in sig.reason


@pytest.mark.parametrize("days, expected", [
    (scenario([], gap_open=100.5), "gap"),                 # no gap
    (scenario([], volume=1500), "relative volume"),        # not in play
])
def test_rejections(days, expected):
    sig, why = entry_on(days)
    assert sig is None and why.startswith(expected)


def test_no_entry_before_news():
    sig, why = entry_on(scenario(ramp(105.8, 0.05, 60)), news_at=datetime(2026, 10, 28, 12, 0, tzinfo=ET))
    assert sig is None


# --- trade simulation ------------------------------------------------------------


def play(after):
    days = scenario(after)
    sig, i = entry_on(days)
    return simulate_trade(PLAN, sig, days[DAY][i:])


def test_winner_hits_target():
    trade = play(ramp(105.8, 0.05, 90))
    assert trade.exit_reason == "target" and trade.r == pytest.approx(1.95, abs=0.03)  # 2R minus slippage


def test_loser_hits_stop():
    trade = play(ramp(105.8, -0.05, 60))
    assert trade.exit_reason == "stop" and trade.r == pytest.approx(-1.0, abs=0.1)


def test_breakeven_stop():
    up = ramp(105.8, 0.05, 25)  # past +1R
    trade = play(up + ramp(up[-1], -0.05, 60))
    assert trade.exit_reason == "breakeven stop" and -0.1 < trade.r < 0  # slippage only


def test_time_exit():
    trade = play([105.9] * 400)
    assert trade.exit_reason == "time exit" and trade.exit_time.strftime("%H:%M") == "15:55"


# --- risk and backtest ---------------------------------------------------------


def test_position_sizing():
    rules = RiskRules()
    assert rules.size(100_000, 50.0, 49.0) == 500        # $500 risk / $1 per share
    assert rules.size(100_000, 50.0, 49.99) == 500       # capped at 25% of equity = 500 shares
    assert rules.can_open("X", set(), set(), -1600, 100_000)[1].startswith("daily loss")
    assert rules.can_open("X", {"A", "B", "C"}, set(), 0, 100_000)[1] == "max open positions"


def test_backtest_end_to_end():
    win, lose = scenario(ramp(105.8, 0.05, 90)), scenario(ramp(105.8, -0.05, 60))
    tickers = {"WIN": win, "LOSE": lose, "FLAT": scenario([], gap_open=100.5), "SPY": calm_market()}
    articles = [article(tickers=(t,)) for t in tickers] + [article(title="Bad Co offering", cats=("offering",), tickers=("BAD",))]
    report = run_backtest(PLAN, RiskRules(), articles, lambda t, d: tickers[t])
    stats = report.stats
    assert stats["trades"] == 2 and stats["win_rate_pct"] == 50.0
    assert stats["expectancy_r"] > 0.4 and stats["profit_factor"] > 1.5
    assert report.end_equity > report.start_equity
    assert any(s[0] == "FLAT" and s[2].startswith("gap") for s in report.skipped)
    json.dumps(report.to_dict(), default=str)


def test_live_gate():
    assert not passes_live_gate({"trades": 5, "expectancy_r": 1, "profit_factor": 3})[0]
    assert not passes_live_gate({"trades": 50, "expectancy_r": -0.1, "profit_factor": 0.9})[0]
    assert passes_live_gate({"trades": 50, "expectancy_r": 0.2, "profit_factor": 1.4})[0]


def test_parse_bars():
    payload = json.dumps({"chart": {"result": [{"timestamp": [1793367000, 1793367060],
        "indicators": {"quote": [{"open": [1, None], "high": [2, 2], "low": [0.5, 1], "close": [1.5, 1], "volume": [100, 5]}]}}]}})
    bars = parse_bars(payload)
    assert len(bars) == 1 and bars[0].t.tzinfo == ET


# --- live loop against the paper broker ----------------------------------------------


def test_trader_trades_a_full_day(tmp_path, capsys):
    days = scenario(ramp(105.8, 0.05, 90))
    all_bars = [b for d in days.values() for b in d]
    broker = PaperBroker(tmp_path / "acct.json", 100_000)
    trader = Trader(PLAN, RiskRules(), broker, bars=lambda t: all_bars, news=lambda: [article()], journal=tmp_path / "j.jsonl")
    t = datetime(2026, 10, 28, 9, 30, tzinfo=ET)
    while t.hour < 16:
        trader.tick(t)
        t += timedelta(minutes=1)
    events = [json.loads(line) for line in (tmp_path / "j.jsonl").read_text().splitlines()]
    kinds = [e["event"] for e in events if e["event"] != "skip"]
    assert kinds == ["entry", "breakeven", "exit"]
    exit_event = events[-1]
    assert exit_event["reason"] == "target" and exit_event["pnl"] > 0
    assert broker.equity() > 100_000 and not broker.positions
    # Reloading picks up the same account, and the ticker is not traded twice.
    assert PaperBroker(tmp_path / "acct.json").traded_today(t.date().isoformat()) == {"ACME"}


def test_trader_ignores_weekends_and_closed_market(tmp_path):
    broker = PaperBroker(tmp_path / "acct.json")
    called = []
    trader = Trader(PLAN, RiskRules(), broker, bars=lambda t: called.append(t) or [], news=lambda: [article()], journal=tmp_path / "j.jsonl")
    trader.tick(datetime(2026, 10, 31, 10, 0, tzinfo=ET))  # Saturday
    trader.tick(datetime(2026, 10, 28, 8, 0, tzinfo=ET))   # pre-market
    assert not called


# --- Alpaca orders -------------------------------------------------------------------


class FakeSession:
    def __init__(self, responses):
        self.headers, self.calls, self.responses = {}, [], responses

    def request(self, method, url, timeout=None, **kw):
        self.calls.append((method, url, kw))

        class R:
            status_code = 200
            text = json.dumps(self.responses.get((method, url.split(".markets")[1]), {}))

            def json(r):
                return json.loads(r.text)

        return R()


def test_alpaca_bracket_and_breakeven(monkeypatch):
    monkeypatch.setenv("ALPACA_API_KEY_ID", "k")
    monkeypatch.setenv("ALPACA_API_SECRET_KEY", "s")
    session = FakeSession({("GET", "/v2/orders"): [{"id": "parent", "type": "market", "status": "filled",
                                                     "legs": [{"id": "tp", "type": "limit", "status": "new"}, {"id": "sl", "type": "stop", "status": "held"}]}]})
    broker = AlpacaBroker(session=session)
    assert broker.base == AlpacaBroker.PAPER
    broker.buy("ACME", 100, 105.8, 104.7, 108.0)
    method, url, kw = session.calls[0]
    assert (method, url.endswith("/v2/orders")) == ("POST", True)
    assert kw["json"]["order_class"] == "bracket" and kw["json"]["stop_loss"] == {"stop_price": "104.70"}
    broker.move_stop("ACME", 105.8)
    assert session.calls[-1][0] == "PATCH" and session.calls[-1][1].endswith("/v2/orders/sl")
    assert session.calls[-1][2]["json"] == {"stop_price": "105.80"}


def test_alpaca_needs_keys(monkeypatch):
    monkeypatch.delenv("ALPACA_API_KEY_ID", raising=False)
    with pytest.raises(RuntimeError, match="ALPACA_API_KEY_ID"):
        AlpacaBroker()


# --- improvements: gap cap, market filter, scale-out and trailing, ranking, archive ----------------


def test_gap_too_big_is_skipped():
    sig, why = entry_on(scenario([], gap_open=120.0))
    assert sig is None and why.startswith("gap +20.0% too big")


def test_market_filter_blocks_weak_tape():
    days = scenario(ramp(105.8, 0.05, 60))
    today, hist = days[DAY], [b for d, b in sorted(days.items()) if d < DAY]
    weak = calm_market(-1.0)
    spy = (weak[DAY], 100.0)
    sig, why = check_entry(PLAN, "ACME", today[:21], hist, datetime(2026, 10, 28, 7, 0, tzinfo=ET), spy)
    assert sig is None and why.startswith("market")
    strong = calm_market(0.4)
    sig, _ = check_entry(PLAN, "ACME", today[:21], hist, datetime(2026, 10, 28, 7, 0, tzinfo=ET), (strong[DAY], 100.0))
    assert sig is not None


def test_backtest_skips_trades_in_weak_market():
    tickers = {"WIN": scenario(ramp(105.8, 0.05, 90)), "SPY": calm_market(-1.0)}
    report = run_backtest(PLAN, RiskRules(), [article(tickers=("WIN",))], lambda t, d: tickers[t])
    assert report.stats["trades"] == 0 and report.skipped[0][2].startswith("market")


def test_scale_out_and_trailing_lets_a_runner_run():
    from dataclasses import replace

    runner = ramp(105.8, 0.05, 150)  # a long trend: about 7R if held
    fixed = play(runner)
    trail_plan = replace(PLAN, scale_out_r=1.0, scale_out_pct=50, trail_bars=10)
    days = scenario(runner + ramp(runner[-1], -0.08, 40))
    sig, i = entry_on(days)
    trailed = simulate_trade(trail_plan, sig, days[DAY][i:])
    assert fixed.exit_reason == "target" and fixed.r < 2
    assert trailed.exit_reason.startswith("trailing stop") and trailed.r > fixed.r + 1


def test_scale_out_on_a_failed_trade_still_banks_half():
    from dataclasses import replace

    plan = replace(PLAN, scale_out_r=1.0, scale_out_pct=50)
    up = ramp(105.8, 0.05, 22)  # just past +1R
    days = scenario(up + ramp(up[-1], -0.05, 60))
    sig, i = entry_on(days)
    trade = simulate_trade(plan, sig, days[DAY][i:])
    assert trade.exit_reason == "breakeven stop (after scale-out)" and 0.4 < trade.r < 0.6


def test_news_strength_ranks_stronger_stories_first():
    from newsspider.strategy import news_strength

    big = {**article(cats=("earnings", "guidance")), "sources": ["A", "B", "C"]}
    small = {**article(cats=("analyst",), sentiment=0.3), "sources": ["A"]}
    assert news_strength(big) > news_strength(small) * 3


def test_breakdown_groups_trades():
    from newsspider.backtest import breakdown

    tickers = {"WIN": scenario(ramp(105.8, 0.05, 90)), "LOSE": scenario(ramp(105.8, -0.05, 60)), "SPY": calm_market()}
    articles = [article(tickers=("WIN",)), article(tickers=("LOSE",), cats=("analyst",))]
    report = run_backtest(PLAN, RiskRules(), articles, lambda t, d: tickers[t])
    groups = breakdown(report.trades)
    assert groups["catalyst"]["earnings"]["expectancy_r"] > 0 > groups["catalyst"]["analyst"]["expectancy_r"]
    assert groups["gap / move"]["4-8%"]["trades"] == 2


def test_bar_archive_keeps_finished_days(tmp_path, monkeypatch):
    from newsspider import bars as bars_mod
    from newsspider.bars import BarArchive

    days = scenario(ramp(105.8, 0.05, 90))
    every = [b for d in days.values() for b in d]
    calls = []

    def fake_fetch(fetcher, ticker, start=None, end=None, extended=False):
        calls.append(ticker)
        return [b for b in every if (start is None or start <= b.t < end)]

    monkeypatch.setattr(bars_mod, "fetch_bars", fake_fetch)
    archive = BarArchive(str(tmp_path / "bars.db"), fetcher=object())
    start = datetime(2026, 10, 20, tzinfo=ET)
    end = datetime(2026, 10, 29, tzinfo=ET)
    first = archive.range("ACME", start, end)
    assert len(first) == len(every) and calls == ["ACME"]
    offline = BarArchive(str(tmp_path / "bars.db"), fetcher=None)  # Yahoo gone: the archive still answers
    assert len(offline.range("ACME", start, end)) == len(every)


def test_trader_scales_out_trails_and_survives_restart(tmp_path):
    from dataclasses import replace

    plan = replace(PLAN, scale_out_r=1.0, scale_out_pct=50, trail_bars=10)
    runner = ramp(105.8, 0.05, 150)
    days = scenario(runner + ramp(runner[-1], -0.08, 40))
    days_spy = calm_market()
    acme = [b for d in days.values() for b in d]
    spy = [b for d in days_spy.values() for b in d]
    bars = lambda t: spy if t == "SPY" else acme  # noqa: E731
    journal, account = tmp_path / "j.jsonl", tmp_path / "acct.json"

    def trader():
        return Trader(plan, RiskRules(), PaperBroker(account, 100_000), bars=bars, news=lambda: [article()], journal=journal)

    bot = trader()
    t = datetime(2026, 10, 28, 9, 30, tzinfo=ET)
    while t < datetime(2026, 10, 28, 10, 30, tzinfo=ET):
        bot.tick(t)
        t += timedelta(minutes=1)
    bot = trader()  # restart mid-trade: the stop and scale-out state come back from the journal
    assert bot.book["ACME"]["scaled"] and bot.book["ACME"]["stop"] > bot.book["ACME"]["entry"]
    while t.hour < 16:
        bot.tick(t)
        t += timedelta(minutes=1)
    events = [json.loads(line) for line in journal.read_text().splitlines()]
    kinds = [e["event"] for e in events if e["event"] not in ("skip", "trail")]
    assert kinds == ["entry", "scale-out", "exit"]
    assert events[-1]["reason"] == "trailing stop" and events[-1]["pnl"] > 0
    half = next(e for e in events if e["event"] == "scale-out")
    assert events[-1]["pnl"] > half["pnl"]  # the runner made more than the half sold at 1R
    assert bot.broker.equity() > 100_000 + 2 * half["pnl"]


# --- walk-forward tuner -----------------------------------------------------------------------


def test_split_by_time_keeps_order():
    from newsspider.tune import split_by_time

    arts = [article(when=datetime(2026, 10, d, 7, 0, tzinfo=ET)) for d in range(1, 11)]
    train, test, cut = split_by_time(arts)
    assert len(train) == 7 and len(test) == 3 and max(a["published"] for a in train) < min(a["published"] for a in test)


def test_tune_recommends_only_what_holds_up_on_unseen_news():
    from newsspider.backtest import Report, Trade
    from newsspider.tune import GRIDS, tune

    def fake_run(plan, arts):
        # Pretend trailing exits earn 0.6R/trade, fixed 3R 0.5R on old news but -0.2R on new, current 0.2R.
        newer = arts and arts[0]["published"] >= "2026-10-08"
        r = 0.2
        if plan.trail_bars:
            r = 0.6
        elif plan.target_r == 3.0:
            r = -0.2 if newer else 0.9
        trades = [Trade("X", DAY, datetime(2026, 10, 28, 10, tzinfo=ET), 100, 99, datetime(2026, 10, 28, 11, tzinfo=ET),
                        100 + r, "t", r, "", "", qty=10, pnl=10 * r) for _ in range(len(arts) * 2)]
        return Report(trades, [], 100_000, 100_000 + sum(t.pnl for t in trades), 1.0)

    arts = [article(when=datetime(2026, 10, d, 7, 0, tzinfo=ET)) for d in range(1, 11)]
    baseline, rows, best, verdict = tune(PLAN, arts, fake_run, GRIDS["regular"], min_trades=5)
    assert rows[0].changes["target_r"] == 3.0          # best on older news...
    assert best is None and "did not beat" in verdict   # ...but it failed on newer news, so no recommendation

    def fake_run_honest(plan, arts):
        r = 0.6 if plan.trail_bars else 0.2
        trades = [Trade("X", DAY, datetime(2026, 10, 28, 10, tzinfo=ET), 100, 99, datetime(2026, 10, 28, 11, tzinfo=ET),
                        100 + r, "t", r, "", "", qty=10, pnl=10 * r) for _ in range(len(arts) * 2)]
        return Report(trades, [], 100_000, 100_000 + sum(t.pnl for t in trades), 1.0)

    baseline, rows, best, verdict = tune(PLAN, arts, fake_run_honest, GRIDS["regular"], min_trades=5)
    assert best is not None and best.changes["trail_bars"] == 10 and verdict.startswith("recommended")
