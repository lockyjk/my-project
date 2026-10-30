@echo off
cd /d "%~dp0"
python -m newsspider bot status
echo.
python -m newsspider bot status --plan 24h
echo.
python -m newsspider bot backtest --since 30d
echo.
python -m newsspider bot backtest --plan 24h --since 30d --report bot_report_24h.json
echo.
python -m newsspider bot tune --since 60d
echo.
python -m newsspider bot tune --plan 24h --since 60d
pause
