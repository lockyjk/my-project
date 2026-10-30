from datetime import date, datetime, timedelta

import pytest

from newsspider.backtest import passes_live_gate
from newsspider.bars import ET, Bar
from newsspider.risk import RiskRules
from newsspider.strategy24 import (
    Plan24, by_session_stats, check_entry_24, find_trade_24, is_open_24_5, news_events, run_backtest_24, session_name,
)

PLAN = Plan24()
WED = date(2026, 10, 28)
NEWS = datetime(2026, 10, 28, 16, 5, tzinfo=ET)  # earnings out after the close


def at(day: date, hh: int, mm: int) -> datetime:
    return datetime(day.year, day.month, day.day, hh, mm, tzinfo=ET)


def bar(t: datetime, o: float, c: float, v: float) -> Bar:
    return Bar(t, o, max(o, c) + 0.03, min(o, c) - 0.03, c, v)


def quiet_after_hours(days_back: int = 6, volume: float = 200) -> list[Bar]:
    out, d = [], WED
    for _ in range(days_back):
        d -= timedelta(days=1)
        if d.weekday() >= 5:
            continue
        out += [bar(at(d, 16, 0) + timedelta(minutes=i), 100, 100, volume) for i in range(240)]
    return out


def reaction_day(after: list[float], news_hh=16, news_mm=5, volume=5000, start_day=WED, pre_volume=200) -> list[Bar]:
    """Quiet before the story, a 15-minute reaction range of 102-103, a pause, then a breakout to 103.3."""
    t0 = at(start_day, news_hh, news_mm)
    pre = [bar(t0 - timedelta(minutes=5 - i), 100, 100, pre_volume) for i in range(5)]
    rng = [102.0, 102.8, 103.0, 102.4, 102.2, 102.9, 102.6, 102.5, 102.7, 102.9, 102.6, 102.4, 102.5, 102.8, 102.6]
    closes = rng + [102.6] * 5 + [103.3] + after
    bars, prev = [], 100.0
    for i, c in enumerate(closes):
        bars.append(bar(t0 + timedelta(minutes=i), prev, c, volume))
        prev = c
    return pre + bars


def ramp(start, step, n):
    return [round(start + step * (i + 1), 4) for i in range(n)]


def story(title="Acme beats estimates, raises guidance", cats=("earnings", "guidance"), when=NEWS, tickers=("ACME",), sentiment=0.7):
    return {"title": title, "catalysts": list(cats), "sentiment": sentiment, "tickers": list(tickers), "published": when.isoformat()}


# --- calendar ------------------------------------------------------------------


def test_sessions_and_24_5_calendar():
    assert session_name(at(WED, 3, 0)) == "overnight"
    assert session_name(at(WED, 7, 0)) == "pre-market"
    assert session_name(at(WED, 12, 0)) == "regular"
    assert session_name(at(WED, 17, 0)) == "after-hours"
    assert session_name(at(WED, 21, 0)) == "overnight"
    assert is_open_24_5(at(WED, 2, 0))
    assert not is_open_24_5(at(date(2026, 10, 31), 12, 0))   # Saturday
    assert not is_open_24_5(at(date(2026, 11, 1), 19, 0))    # Sunday before 20:00
    assert is_open_24_5(at(date(2026, 11, 1), 20, 0))        # Sunday open
    assert not is_open_24_5(at(date(2026, 10, 30), 20, 0))   # Friday close


# --- news events -----------------------------------------------------------------


def test_weekend_news_waits_for_sunday_open():
    sat = at(date(2026, 10, 31), 10, 0)
    [(ticker, when, _)] = news_events([story(when=sat)], PLAN)
    assert when == at(date(2026, 11, 1), 20, 0)


def test_veto_within_12_hours_and_once_per_24h():
    dilution = story(title="Acme prices offering", cats=("offering",), when=NEWS + timedelta(hours=3), sentiment=-0.3)
    assert news_events([story(), dilution], PLAN) == []
    far = story(title="Acme prices offering", cats=("offering",), when=NEWS + timedelta(hours=20), sentiment=-0.3)
    assert len(news_events([story(), far], PLAN)) == 1
    again = story(title="Acme raises outlook again", when=NEWS + timedelta(hours=5))
    assert len(news_events([story(), again], PLAN)) == 1


# --- entries -----------------------------------------------------------------------


def test_after_hours_breakout_signal():
    bars = quiet_after_hours() + reaction_day(ramp(103.3, 0.03, 60))
    trade, reason = find_trade_24(PLAN, "ACME", bars, NEWS)
    assert trade is not None, reason
    assert reason.startswith("after-hours:") and "x volume" in reason
    assert trade.entry_time == at(WED, 16, 26)


@pytest.mark.parametrize("bars, expected", [
    (quiet_after_hours() + reaction_day([], volume=300), "relative volume"),
    (quiet_after_hours(volume=20) + reaction_day([], volume=100, pre_volume=20), "too thin"),  # 5x volume but only ~$214k
])
def test_rejections(bars, expected):
    trade, reason = find_trade_24(PLAN, "ACME", bars, NEWS)
    assert trade is None and reason.startswith(expected), reason


def test_small_move_rejected():
    bars = quiet_after_hours() + [Bar(b.t, b.o * 0.98, b.h * 0.98, b.l * 0.98, b.c * 0.98, b.v) if b.t >= NEWS else b
                                  for b in reaction_day([])]  # tops out about +1.2%
    trade, reason = find_trade_24(PLAN, "ACME", bars, NEWS)
    assert trade is None and reason.startswith("move"), reason


def test_no_lookahead_before_news():
    bars = quiet_after_hours() + reaction_day(ramp(103.3, 0.03, 60))
    early = [b for b in bars if b.t < NEWS]
    assert check_entry_24(PLAN, "ACME", early, NEWS)[1] == "news not out yet"


# --- exits ---------------------------------------------------------------------


def test_target_stop_and_max_hold():
    base = quiet_after_hours()
    win, _ = find_trade_24(PLAN, "ACME", base + reaction_day(ramp(103.3, 0.03, 120)), NEWS)
    assert win.exit_reason == "target" and 1.6 < win.r < 2.0  # 2R less 0.15% slippage each side
    lose, _ = find_trade_24(PLAN, "ACME", base + reaction_day(ramp(103.3, -0.03, 60)), NEWS)
    assert lose.exit_reason == "stop" and lose.r < -1
    flat, _ = find_trade_24(PLAN, "ACME", base + reaction_day([103.35] * 400), NEWS)
    assert flat.exit_reason == "time exit" and flat.exit_time == at(WED, 19, 55)  # no overnight prices: flat by 20:00
    held, _ = find_trade_24(Plan24(overnight_data=True), "ACME", base + reaction_day([103.35] * 400), NEWS)
    assert (held.exit_time - held.entry_time) == timedelta(minutes=240)  # with overnight data: 4-hour max hold


def test_flat_before_the_weekend():
    fri = date(2026, 10, 30)
    news = at(fri, 18, 30)
    bars = quiet_after_hours() + reaction_day([103.35] * 120, news_hh=18, news_mm=30, start_day=fri)
    trade, _ = find_trade_24(PLAN, "ACME", bars, news)
    assert trade.exit_reason == "time exit" and trade.exit_time == at(fri, 19, 55)


# --- full backtest -------------------------------------------------------------------


def test_backtest_24_end_to_end():
    base = quiet_after_hours()
    data = {
        "WIN": base + reaction_day(ramp(103.3, 0.03, 120)),
        "LOSE": base + reaction_day(ramp(103.3, -0.03, 60)),
        "THIN": quiet_after_hours(volume=20) + reaction_day([], volume=100, pre_volume=20),
    }
    articles = [story(tickers=(t,)) for t in data]
    report = run_backtest_24(PLAN, RiskRules(), articles, lambda t, when: data[t])
    stats = report.stats
    assert stats["trades"] == 2 and stats["win_rate_pct"] == 50.0
    assert any(s[0] == "THIN" and s[2].startswith("too thin") for s in report.skipped)
    sessions = by_session_stats(report.trades)
    assert sessions["after-hours"]["trades"] == 2
    assert not passes_live_gate(stats)[0]  # two trades prove nothing


# --- live paper trading ---------------------------------------------------------------


def test_paper_trader_24_after_hours_day(tmp_path):
    from newsspider.broker import PaperBroker
    from newsspider.trader24 import Trader24
    import json

    bars = quiet_after_hours() + reaction_day(ramp(103.3, 0.03, 120))
    broker = PaperBroker(tmp_path / "acct.json", 100_000)
    trader = Trader24(PLAN, RiskRules(), broker, bars=lambda t: bars, news=lambda: [story()], journal=tmp_path / "j.jsonl")
    t = at(WED, 15, 0)
    while t < at(WED, 21, 0):
        trader.tick(t)
        t += timedelta(minutes=1)
    events = [json.loads(line) for line in (tmp_path / "j.jsonl").read_text().splitlines()]
    trades = [e for e in events if e["event"] != "skip"]
    assert [e["event"] for e in trades] == ["entry", "breakeven", "exit"]
    assert trades[0]["at"].startswith("2026-10-28T16:26") and trades[-1]["reason"] == "target"
    assert broker.equity() > 100_000 and not broker.positions


def test_paper_trader_24_flat_by_8pm_and_skips_without_prices(tmp_path):
    from newsspider.broker import PaperBroker
    from newsspider.trader24 import Trader24
    import json

    bars = quiet_after_hours() + reaction_day([103.35] * 400)
    broker = PaperBroker(tmp_path / "acct.json", 100_000)
    trader = Trader24(PLAN, RiskRules(), broker, bars=lambda t: bars, news=lambda: [story()], journal=tmp_path / "j.jsonl")
    t = at(WED, 16, 0)
    while t < at(WED, 20, 30):
        trader.tick(t)
        t += timedelta(minutes=1)
    exits = [json.loads(line) for line in (tmp_path / "j.jsonl").read_text().splitlines() if '"exit"' in line]
    assert exits and exits[0]["reason"] == "time exit" and exits[0]["at"].startswith("2026-10-28T19:55")
    assert not broker.positions
    # Overnight news with no price feed: logged as a skip, never traded.
    night = story(when=at(WED, 23, 0), tickers=("NITE",))
    trader.news = lambda: [night]
    trader.tick(at(WED, 23, 30))
    assert "no live prices" in (tmp_path / "j.jsonl").read_text()
