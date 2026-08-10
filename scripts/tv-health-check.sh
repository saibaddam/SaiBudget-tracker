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
# Env:    TV_CDP_PORT / CDP_PORT   CDP port  (default 9222)
#         TV_CDP_HOST / CDP_HOST   CDP host  (default 127.0.0.1)
#
# Those are the connector's own variables (see its src/connection.js), so the
# endpoint probed below is by construction the one the connector will dial --
# a private variable here could pass the probe and still leave the CLI talking
# to a different port.
#
# Exits 0 when every check passes, 1 otherwise.

set -uo pipefail

PORT="${TV_CDP_PORT:-${CDP_PORT:-9222}}"
HOST="${TV_CDP_HOST:-${CDP_HOST:-127.0.0.1}}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MCP_JSON="$REPO_ROOT/.mcp.json"

failures=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; failures=$((failures + 1)); }
hint() { printf '        -> %s\n' "$1"; }

printf '\nTradingView MCP health check (%s:%s)\n\n' "$HOST" "$PORT"

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

# 3. The server clone itself, at whatever path .mcp.json points to, and its
#    dependencies.
tv_root=""
deps_ok=0
if [ -n "$server_js" ]; then
  if [ -f "$server_js" ]; then
    pass "server present at $server_js"
    tv_root="$(cd -- "$(dirname -- "$server_js")/.." && pwd)"

    # A skipped `npm install` surfaces far from its cause: the connector dies at
    # import time with ERR_MODULE_NOT_FOUND, which reads like a connection fault
    # rather than a missing dependency. Name it here instead.
    if [ -d "$tv_root/node_modules" ]; then
      pass "dependencies installed"
      deps_ok=1
    else
      fail "dependencies not installed"
      hint "cd $tv_root && npm install"
    fi
  else
    fail "server missing at $server_js"
    hint "git clone https://github.com/tradesdontlie/tradingview-mcp.git ~/Documents/tradingview-mcp && (cd ~/Documents/tradingview-mcp && npm install)"
    hint "or point .mcp.json args[0] at wherever you cloned it"
  fi
fi

# 4. The CDP debug port -- isolates a TradingView launch problem from an MCP
#    configuration problem. Nothing downstream can work until this returns JSON.
port_ok=0
version_json=$(curl -sS --max-time 5 --noproxy "$HOST,127.0.0.1,localhost" \
  "http://$HOST:$PORT/json/version" 2>&1)
curl_rc=$?

if [ "$curl_rc" -ne 0 ] || [ -z "$version_json" ]; then
  fail "no CDP endpoint on $HOST:$PORT"
  hint "quit TradingView completely, then relaunch it with --remote-debugging-port=$PORT"
  hint "an already-running instance does not have the debug port open"
  hint "in a remote/cloud session this failure is expected -- the bridge is local-only"
elif printf '%s' "$version_json" | grep -q 'TVDesktop'; then
  pass "TradingView Desktop answering CDP on $HOST:$PORT"
  port_ok=1
else
  # Something is on the port, but it is not TradingView -- most often a stray
  # Chrome or another Electron app already holding 9222.
  fail "$HOST:$PORT is open but is not TradingView Desktop"
  hint "another Chromium app is holding the port; close it, or launch TradingView on a free port and set TV_CDP_PORT to match"
  hint "got: $(printf '%s' "$version_json" | head -c 200)"
fi

# 5. Live status through the connector's own CLI -- the same reading the
#    tv_health_check tool reports, but without restarting Claude Code.
if [ -n "$tv_root" ] && [ "$deps_ok" -eq 1 ] && [ "$port_ok" -eq 1 ]; then
  cli="$tv_root/src/cli/index.js"

  if [ ! -f "$cli" ]; then
    fail "connector CLI not found at $cli"
    hint "the clone looks incomplete -- re-clone and run npm install"
  else
    # Pass the resolved endpoint through explicitly: the CLI defaults to
    # 127.0.0.1:9222, so without this it could dial somewhere other than the
    # endpoint just verified above.
    status=$(cd "$tv_root" && TV_CDP_HOST="$HOST" TV_CDP_PORT="$PORT" \
      node src/cli/index.js status 2>&1)
    cli_rc=$?

    if [ "$cli_rc" -ne 0 ]; then
      # A crash is not the same as an unhealthy-but-answering connector; do not
      # read the key checks below into a stack trace.
      fail "connector CLI exited $cli_rc without reporting status"

      # It reports failures as JSON ({"success":false,"error":...}); fall back
      # to a raw trace only if that shape is absent.
      detail=$(printf '%s' "$status" \
        | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1)
      [ -z "$detail" ] && detail=$(printf '%s' "$status" | grep -m1 'Error')
      [ -z "$detail" ] && detail=$(printf '%s' "$status" | grep -m1 '[^[:space:]]')
      [ -n "$detail" ] && hint "$(printf '%s' "$detail" | head -c 200)"

      # Exit 2 is the connector's dedicated connection-failure code.
      if [ "$cli_rc" -eq 2 ]; then
        hint "the port answered but the chart target did not -- open a chart tab in TradingView and retry"
      fi
    else
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
