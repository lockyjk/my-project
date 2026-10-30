@echo off
rem Paper-trade both plans side by side, each with its own $100,000 simulated account.
rem First time only: pip install -e .   and put your email in config.toml user_agent.
cd /d "%~dp0"
start "24/5 News Reaction (paper) + news spider" cmd /k python -m newsspider bot run --plan 24h
start "Catalyst Momentum (paper)" cmd /k python -m newsspider bot run --no-crawl
echo Two windows opened. Leave them running. Run paper-report.bat any time to see results.
