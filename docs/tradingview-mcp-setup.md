# TradingView MCP Connector — Local Setup

This project registers the [`tradingview-mcp`](https://github.com/tradesdontlie/tradingview-mcp)
connector in [`.mcp.json`](../.mcp.json). It is a **local bridge**: it drives your
**TradingView Desktop** app over the Chrome DevTools Protocol on `localhost:9222`.
It must run on your own machine — it does not work in a remote/cloud session.

## 1. Clone and install the server

By default `.mcp.json` expects the server at `$HOME/tradingview-mcp`:

```bash
git clone https://github.com/tradesdontlie/tradingview-mcp.git ~/tradingview-mcp
cd ~/tradingview-mcp
npm install
```

If you clone it somewhere else, update the path in `.mcp.json`
(`args` → `.../src/server.js`) accordingly. On Windows, use an absolute path
such as `C:\\Users\\you\\tradingview-mcp\\src\\server.js`.

## 2. Launch TradingView with the debug protocol

Start TradingView Desktop with Chrome DevTools enabled on port 9222:

- macOS:   `~/tradingview-mcp/scripts/launch_tv_debug_mac.sh`
- Windows: `tradingview-mcp\scripts\launch_tv_debug.bat`
- Linux:   `~/tradingview-mcp/scripts/launch_tv_debug_linux.sh`

Manual equivalent: `/path/to/TradingView --remote-debugging-port=9222`

## 3. Use it

No API keys or environment variables are required. Restart Claude Code so it
picks up `.mcp.json`, then verify with the `tv_health_check` tool, or:

```bash
cd ~/tradingview-mcp && node src/cli/index.js status
```
