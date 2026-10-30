"""Walk-forward tuning: pick settings on older news, then check them on newer news they never saw.

Tuning on all the data and keeping the best result mostly finds settings that fit the past by luck.
Here the variants compete on the first 70% of the news (by time) and only the winner's result on the
last 30% counts. A change is recommended only if it also beats the current settings on that 30%.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Callable

from .backtest import Report

EXITS = {
    "fixed 2R target": {"target_r": 2.0, "scale_out_r": 0.0, "trail_bars": 0},
    "fixed 3R target": {"target_r": 3.0, "scale_out_r": 0.0, "trail_bars": 0},
    "half at 1R, trail rest": {"scale_out_r": 1.0, "scale_out_pct": 50.0, "trail_bars": 10},
}
GRIDS = {
    "regular": {"min_gap_pct": [2.0, 3.0], "min_rel_volume": [2.0, 3.0], "exit": list(EXITS), "market_filter": [True, False]},
    "24h": {"min_move_pct": [2.0, 3.0], "min_rel_volume": [3.0, 5.0], "exit": list(EXITS), "market_filter": [True, False]},
}


@dataclass
class Row:
    name: str
    changes: dict
    train: dict
    test: dict | None = None


def split_by_time(articles: list[dict], train_share: float = 0.7) -> tuple[list[dict], list[dict], datetime | None]:
    ordered = sorted(articles, key=lambda a: a["published"])
    if len(ordered) < 2:
        return ordered, [], None
    cut = ordered[int(len(ordered) * train_share)]["published"]
    return [a for a in ordered if a["published"] < cut], [a for a in ordered if a["published"] >= cut], datetime.fromisoformat(cut)


def variants(base, grid: dict) -> list[tuple[str, dict, object]]:
    keys = list(grid)
    out = []
    for values in itertools.product(*(grid[k] for k in keys)):
        changes = {}
        for key, value in zip(keys, values):
            changes.update(EXITS[value] if key == "exit" else {key: value})
        label = ", ".join(f"{k}={v}" if k != "exit" else str(v) for k, v in zip(keys, values))
        out.append((label, changes, replace(base, **changes)))
    return out


def tune(
    base,
    articles: list[dict],
    run: Callable[[object, list[dict]], Report],
    grid: dict,
    min_trades: int = 10,
    finalists: int = 5,
) -> tuple[Row, list[Row], Row | None, str]:
    """Returns (current settings, finalists with test results, recommendation or None, verdict)."""
    train, test, cut = split_by_time(articles)
    baseline = Row("current settings", {}, run(base, train).stats, run(base, test).stats)
    scored = []
    for label, changes, plan in variants(base, grid):
        stats = run(plan, train).stats
        if stats["trades"] >= min_trades:
            scored.append((Row(label, changes, stats), plan))
    scored.sort(key=lambda rp: (rp[0].train["expectancy_r"], rp[0].train["profit_factor"]), reverse=True)
    rows = []
    for row, plan in scored[:finalists]:
        row.test = run(plan, test).stats
        rows.append(row)
    when = f" (split at {cut:%Y-%m-%d %H:%M})" if cut else ""
    if not rows:
        return baseline, rows, None, f"not enough trades to tune: no variant reached {min_trades} trades in the older 70%{when}"
    best = rows[0]
    if best.test["trades"] < max(3, min_trades // 3):
        return baseline, rows, None, f"too few trades in the newer 30% to confirm anything{when}"
    if best.test["expectancy_r"] <= baseline.test["expectancy_r"] or best.test["expectancy_r"] <= 0:
        return baseline, rows, None, f"the best variant did not beat current settings on unseen news; keep current settings{when}"
    return baseline, rows, best, f"recommended: it won on older news and also beat current settings on newer, unseen news{when}"


def as_toml(changes: dict) -> str:
    def fmt(v):
        return str(v).lower() if isinstance(v, bool) else repr(v)

    return "\n".join(f"{k} = {fmt(v)}" for k, v in changes.items())
