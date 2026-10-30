"""Render a parsed filing as a self-contained page where an animated spider reads it."""

from __future__ import annotations

import html
import json
from pathlib import Path

from .filing import Filing

TEMPLATE = (Path(__file__).parent / "spider_report.html").read_text()


def render(filing: Filing, caption: str = "", brand: str = "newsspider") -> str:
    data = json.dumps(filing.data()).replace("</", "<\\/")
    return (
        TEMPLATE.replace("__TITLE__", html.escape(f"{filing.ticker} {filing.form} spider"))
        .replace("__CAPTION__", html.escape(caption))
        .replace("__BRAND__", html.escape(brand))
        .replace("__DATA__", data)
        .replace("__DOCUMENT__", filing.html)
    )
