# SaiBudget-tracker

A single-file trading P&L tracker (`trading-tracker.html`) that logs daily wins
and losses against a weekly target, saving to a local JSON file via the File
System Access API.

## TradingView integration

`docs/tradingview-desktop-setup.md` walks through connecting **Claude Code
Desktop** to the **TradingView desktop app** over the Chrome DevTools Protocol,
so Claude can read and drive your charts.

```bash
./scripts/setup-tradingview-mcp.sh        # one-time install + MCP registration
./scripts/launch-tradingview-debug.sh     # start TradingView with CDP enabled
```

Both steps must run on your own machine — a remote Claude Code session cannot
reach the desktop app.
