#!/usr/bin/env bash
#
# Health check for the TradingView MCP connector registered in .mcp.json.
#
# Runs the setup guide's verification steps in one pass, from the outside in:
# node -> connector config -> server clone -> CDP debug port -> live CLI status.
# Each check prints PASS/FAIL with the fix for that specific failure, so the
# first FAIL tells you which step of docs/tradingview-mcp-setup.md to redo.
#
# This is local-only. TradingView Desktop must be running on this machine with
# --remote-debugging-port; in a remote/cloud session the port check always fails.
#
# Usage:  scripts/tv-health-check.sh
# Env:    TV_DEBUG_PORT   CDP port to probe (default 9222)
#
# Exits 0 when every check passes, 1 otherwise.

set -uo pipefail

PORT="${TV_DEBUG_PORT:-9222}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MCP_JSON="$REPO_ROOT/.mcp.json"

failures=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; failures=$((failures + 1)); }
hint() { printf '        -> %s\n' "$1"; }

printf '\nTradingView MCP health check (port %s)\n\n' "$PORT"

# 1. node -- required to run both the MCP server and the CLI below.
if command -v node >/dev/null 2>&1; then
  pass "node present ($(node --version))"
else
  fail "node not found on PATH"
  hint "install Node.js; the connector and its CLI are both node programs"
  printf '\nStopping: every remaining check needs node.\n\n'
  exit 1
fi

# 2. .mcp.json -- must parse and register the connector. A syntax error here is
#    silent in Claude Code: the connector simply never appears.
server_js=""
if [ ! -f "$MCP_JSON" ]; then
  fail ".mcp.json not found at $MCP_JSON"
  hint "run this script from a checkout of the repository"
else
  server_js=$(node -e '
    const fs = require("fs");
    try {
      const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const tv = (cfg.mcpServers || {}).tradingview;
      if (!tv) throw new Error("no mcpServers.tradingview entry");
      const arg = (tv.args || [])[0];
      if (!arg) throw new Error("mcpServers.tradingview has no args[0] server path");
      // Claude Code expands ${VAR} in .mcp.json; mirror that so the path we
      // check is the same one the connector will actually launch.
      process.stdout.write(arg.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (m, v) => process.env[v] ?? m));
    } catch (e) {
      // First line only -- a JSON.parse stack trace is noise next to its reason.
      process.stderr.write(String(e.message).split("\n")[0]);
      process.exit(1);
    }
  ' "$MCP_JSON" 2>&1)

  if [ $? -ne 0 ]; then
    fail ".mcp.json unreadable or missing the tradingview connector"
    hint "$server_js"
    server_js=""
  else
    pass "connector registered in .mcp.json"
  fi
fi

# 3. The server clone itself, at whatever path .mcp.json points to.
if [ -n "$server_js" ]; then
  if [ -f "$server_js" ]; then
    pass "server present at $server_js"
  else
    fail "server missing at $server_js"
    hint "git clone https://github.com/tradesdontlie/tradingview-mcp.git ~/tradingview-mcp && (cd ~/tradingview-mcp && npm install)"
    hint "or point .mcp.json args[0] at wherever you cloned it"
  fi
fi

# 4. The CDP debug port -- isolates a TradingView launch problem from an MCP
#    configuration problem. Nothing downstream can work until this returns JSON.
port_ok=0
version_json=$(curl -sS --max-time 5 --noproxy '127.0.0.1,localhost' \
  "http://127.0.0.1:$PORT/json/version" 2>&1)
curl_rc=$?

if [ "$curl_rc" -ne 0 ] || [ -z "$version_json" ]; then
  fail "no CDP endpoint on 127.0.0.1:$PORT"
  hint "quit TradingView completely, then relaunch it with --remote-debugging-port=$PORT"
  hint "an already-running instance does not have the debug port open"
  hint "in a remote/cloud session this failure is expected -- the bridge is local-only"
elif printf '%s' "$version_json" | grep -q 'TVDesktop'; then
  pass "TradingView Desktop answering CDP on port $PORT"
  port_ok=1
else
  # Something is on the port, but it is not TradingView -- most often a stray
  # Chrome or another Electron app already holding 9222.
  fail "port $PORT is open but is not TradingView Desktop"
  hint "another Chromium app is holding the port; close it, or set TV_DEBUG_PORT and match it in the launch flag"
  hint "got: $(printf '%s' "$version_json" | head -c 200)"
fi

# 5. Live status through the connector's own CLI -- the same reading the
#    tv_health_check tool reports, but without restarting Claude Code.
if [ -n "$server_js" ] && [ "$port_ok" -eq 1 ]; then
  tv_root="$(cd -- "$(dirname -- "$server_js")/.." && pwd)"
  cli="$tv_root/src/cli/index.js"

  if [ ! -f "$cli" ]; then
    fail "connector CLI not found at $cli"
    hint "the clone looks incomplete -- re-clone and run npm install"
  else
    status=$(cd "$tv_root" && node src/cli/index.js status 2>&1)

    if printf '%s' "$status" | grep -Eq '"cdp_connected"[[:space:]]*:[[:space:]]*true'; then
      pass "cdp_connected: true"
    else
      fail "cdp_connected is not true"
      hint "TradingView may still be loading -- wait a few seconds and retry"
    fi

    if printf '%s' "$status" | grep -Eq '"api_available"[[:space:]]*:[[:space:]]*true'; then
      pass "api_available: true"
    else
      fail "api_available is not true"
      hint "the chart widget has not finished initialising -- open a chart tab and retry"
    fi

    printf '\nCLI status output:\n'
    printf '%s\n' "$status" | sed 's/^/  /'
  fi
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'All checks passed -- the connector is healthy.\n\n'
  exit 0
fi

printf '%d check(s) failed. See docs/tradingview-mcp-setup.md for the full setup.\n\n' "$failures"
exit 1
