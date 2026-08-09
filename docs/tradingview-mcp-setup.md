# TradingView MCP Connector — Local Setup

This project registers the [`tradingview-mcp`](https://github.com/tradesdontlie/tradingview-mcp)
connector in [`.mcp.json`](../.mcp.json). It is a **local bridge**: it drives your
**TradingView Desktop** app over the Chrome DevTools Protocol on `localhost:9222`.
It must run on your own machine — it does not work in a remote/cloud session.

> **Cloud sessions fail confusingly.** Because this config is committed, a
> remote session (Claude Code on the web) will also start the server — inside
> its own container, where no TradingView is running. The `tv_*` and `chart_*`
> tools therefore *appear* to be available and then fail with
> `CDP connection failed after 5 attempts`. That is expected: run these tools
> from Claude Code on your own machine.

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

Manual equivalents:

```bash
# macOS
/Applications/TradingView.app/Contents/MacOS/TradingView --remote-debugging-port=9222
# Linux
/opt/TradingView/tradingview --remote-debugging-port=9222
```

Quit TradingView completely first — an already-running instance will not have
the debug port open, and relaunching without quitting silently reuses it.

On Windows, TradingView now ships only as an MSIX package, so launch it via
`scripts/launch_tv_debug.bat` (it resolves the install through `Get-AppxPackage`
without needing admin rights). Never run `icacls` against `WindowsApps` to work
around an "Access is denied" error — it fails and can break app servicing.

## 3. Verify the debug port

Do this before anything else — it isolates a TradingView launch problem from an
MCP configuration problem:

```bash
curl http://127.0.0.1:9222/json/version
```

JSON with a `TVDesktop` user-agent means the bridge has something to connect to.
`Connection refused` means step 2 did not take; nothing downstream can work
until this returns JSON.

## 4. Use it

No API keys or environment variables are required. Restart Claude Code so it
picks up `.mcp.json`, then verify with the `tv_health_check` tool, or via the
CLI (which talks to the port directly and needs no restart):

```bash
cd ~/tradingview-mcp && node src/cli/index.js status
```

A healthy response reports `"cdp_connected": true` and `"api_available": true`
alongside the live chart's symbol and resolution. Then, for example:

```bash
node src/cli/index.js symbol AAPL
node src/cli/index.js timeframe 15
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `CDP connection failed` / `ECONNREFUSED` | TradingView not running with `--remote-debugging-port=9222`, or port blocked — redo steps 2–3 |
| Fails only in a web/cloud session | Expected — the bridge is local-only, see the note at the top |
| Connector missing in Claude Code | `.mcp.json` syntax error, or Claude Code was not restarted |
| Windows "Access is denied" from `WindowsApps` | Use `scripts/launch_tv_debug.bat` or the `tv_launch` tool's copy-fallback |
| Tools return stale data | TradingView is still loading — wait a few seconds and retry |
| Symbol resolves to an unexpected feed (`BATS:AAPL`) | TradingView picked its default feed; pass an explicit prefix, e.g. `NASDAQ:AAPL` |
