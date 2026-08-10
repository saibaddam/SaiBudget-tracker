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

`.mcp.json` expects the server at `$HOME/Documents/tradingview-mcp`:

```bash
git clone https://github.com/tradesdontlie/tradingview-mcp.git ~/Documents/tradingview-mcp
cd ~/Documents/tradingview-mcp
npm install
```

If you clone it somewhere else, update the path in `.mcp.json`
(`args` → `.../src/server.js`) accordingly. On Windows, `${HOME}` is usually
unset (the variable is `USERPROFILE`), so use an absolute path such as
`C:\\Users\\you\\Documents\\tradingview-mcp\\src\\server.js`.

## 2. Launch TradingView with the debug protocol

Start TradingView Desktop with Chrome DevTools enabled on port 9222:

- macOS:   `~/Documents/tradingview-mcp/scripts/launch_tv_debug_mac.sh`
- Windows: `tradingview-mcp\scripts\launch_tv_debug.bat`
- Linux:   `~/Documents/tradingview-mcp/scripts/launch_tv_debug_linux.sh`

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

### Or run the whole check at once

[`scripts/tv-health-check.sh`](../scripts/tv-health-check.sh) runs every
verification in this guide in order — node, the `.mcp.json` entry, the server
clone, its installed dependencies, the debug port, and the live
`cdp_connected` / `api_available` reading — and prints the fix next to whatever
fails:

```bash
./scripts/tv-health-check.sh
```

It exits `0` only when all checks pass, so it also works as a preflight in a
shell script. If you launched TradingView on a port other than 9222, set
`TV_CDP_PORT` — that is the connector's own variable, so the script and the
bridge stay pointed at the same endpoint:

```bash
TV_CDP_PORT=9333 ./scripts/tv-health-check.sh
```

Being local-only, it always fails the port check in a cloud session.

## 4. Use it

No API keys or environment variables are required. Restart Claude Code so it
picks up `.mcp.json`, then verify with the `tv_health_check` tool, or via the
CLI (which talks to the port directly and needs no restart):

```bash
cd ~/Documents/tradingview-mcp && node src/cli/index.js status
```

A healthy response reports `"cdp_connected": true` and `"api_available": true`
alongside the live chart's symbol and resolution. Then, for example:

```bash
node src/cli/index.js symbol AAPL
node src/cli/index.js timeframe 15
```

## Troubleshooting

Run `./scripts/tv-health-check.sh` first — it names the failing step directly.

| Symptom | Cause / fix |
|---|---|
| `CDP connection failed` / `ECONNREFUSED` | TradingView not running with `--remote-debugging-port=9222`, or port blocked — redo steps 2–3 |
| Fails only in a web/cloud session | Expected — the bridge is local-only, see the note at the top |
| Port 9222 answers, but not as `TVDesktop` | A stray Chrome/Electron app already holds the port — close it, or launch TradingView on another port and set `TV_CDP_PORT` to match |
| `ERR_MODULE_NOT_FOUND` from the connector | `npm install` was never run in the clone — the health check reports this as "dependencies not installed" |
| `No TradingView chart target found` (CLI exit 2) | TradingView is running with the debug port open but has no chart tab — open one and retry |
| Connector missing in Claude Code | `.mcp.json` syntax error, or Claude Code was not restarted |
| Windows "Access is denied" from `WindowsApps` | Use `scripts/launch_tv_debug.bat` or the `tv_launch` tool's copy-fallback |
| Tools return stale data | TradingView is still loading — wait a few seconds and retry |
| Symbol resolves to an unexpected feed (`BATS:AAPL`) | TradingView picked its default feed; pass an explicit prefix, e.g. `NASDAQ:AAPL` |
