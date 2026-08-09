# Connecting Claude Code Desktop to the TradingView desktop app

This connects **Claude Code running on your own machine** to the **TradingView
desktop app**, so you can ask Claude to read your charts, switch symbols and
timeframes, apply indicators, and write Pine Script — against the TradingView
window you already have open.

## How the connection actually works

TradingView's desktop app is an Electron app, which means it can expose the
**Chrome DevTools Protocol (CDP)** on a local port. An open-source MCP server,
[`tradesdontlie/tradingview-mcp`](https://github.com/tradesdontlie/tradingview-mcp),
attaches to that port and exposes TradingView to Claude Code as MCP tools.

```
Claude Code Desktop  ──MCP(stdio)──>  tradingview-mcp  ──CDP :9222──>  TradingView.app
```

Everything runs locally on your machine. There is no TradingView cloud API in
this path, and no data leaves your computer.

### This must be done locally

A remote Claude Code session (claude.ai/code, GitHub Actions, any cloud
container) runs on a different machine and **cannot** reach `localhost:9222` on
your laptop. Run the steps below in **Claude Code Desktop**.

## Prerequisites

- TradingView **desktop app**, signed in (a paid TradingView plan is required
  for the desktop app)
- **Node.js 18+** and **git**
- **Claude Code Desktop**
- macOS, Windows, or Linux

## Setup

### 1. Install the MCP server

From this repo, on your own machine:

```bash
./scripts/setup-tradingview-mcp.sh
```

This clones `tradingview-mcp` to `~/tools/tradingview-mcp` (override with
`TRADINGVIEW_MCP_HOME`), installs its dependencies, and registers a
project-scoped `tradingview` MCP server via `claude mcp add` — falling back to
writing `.mcp.json` directly if the `claude` CLI isn't on your PATH.

`.mcp.json` is git-ignored because it contains an absolute path specific to
your machine. `.mcp.json.example` is the committed template.

### 2. Launch TradingView with debugging enabled

CDP can only be turned on **at launch**, so TradingView has to be started with
the flag rather than opened from the dock or Start menu:

```bash
./scripts/launch-tradingview-debug.sh          # macOS / Linux
scripts\launch-tradingview-debug.bat           # Windows
```

The script finds the app, restarts it if it's already running without CDP
(it asks first), and waits until `http://127.0.0.1:9222/json/version` responds.
Pass a different port as the first argument if 9222 is taken.

Equivalent manual launch:

```bash
/Applications/TradingView.app/Contents/MacOS/TradingView --remote-debugging-port=9222
```

### 3. Verify from Claude Code

Open this project in Claude Code Desktop, approve the project-scoped MCP server
when prompted, then ask:

> Use `tv_health_check` to verify TradingView is connected

Once it's green, things like this work:

> Show me RSI on the EUR/USD 4-hour chart
>
> Switch the chart to NASDAQ:TSLA daily and screenshot it
>
> Read the current chart state and tell me which indicators are loaded

## What you get

The server exposes ~78 tools, including:

| Area | Tools |
| --- | --- |
| Chart reading | `chart_get_state`, `data_get_ohlcv`, `data_get_study_values`, `quote_get` |
| Chart control | `chart_set_symbol`, `chart_set_timeframe`, `chart_set_type`, `chart_manage_indicator` |
| Pine Script | `pine_new`, `pine_set_source`, `pine_smart_compile`, `pine_get_errors`, `pine_save` |
| Bar replay | `replay_start`, `replay_step`, `replay_autoplay`, `replay_trade` |
| Drawing & alerts | `draw_shape`, `alert_create`, `alert_list`, `capture_screenshot` |
| Multi-pane | `pane_set_layout`, `pane_set_symbol`, `pane_list` |
| Streaming | quote / bar / indicator-value streams |

## Troubleshooting

**`tv_health_check` fails or the port never answers**
TradingView was probably started normally at some point and is still running
without CDP. Fully quit it and re-run the launch script — attaching after the
fact is not possible.

**Port 9222 already in use**
Another Chromium app has it. Use a different port on both sides:
`./scripts/launch-tradingview-debug.sh 9333`.

**The MCP server doesn't appear in Claude Code**
Run `claude mcp list`. Project-scoped servers need one-time approval; if you
declined it, re-approve with `claude mcp reset-project-choices`.

**Tools worked yesterday and broke today**
The server drives TradingView's internal, undocumented interfaces, so a
TradingView update can break individual tools. Update the server:
`git -C ~/tools/tradingview-mcp pull && npm --prefix ~/tools/tradingview-mcp install`.

## Limitations and terms of use

- The MCP server is a **community project, not affiliated with TradingView**,
  and it drives undocumented internal interfaces that can change without notice.
- It **does not place real trades** — it's chart and Pine Script interaction only.
- It **cannot unlock features** your TradingView plan doesn't already include.
- TradingView's Terms of Use restrict automated data collection and non-display
  use of their data. Using this for your own charts on your own machine is what
  it's built for; redistributing or bulk-harvesting the data is on you to avoid.
