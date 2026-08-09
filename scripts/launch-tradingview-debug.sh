#!/usr/bin/env bash
# Launch the TradingView desktop app with Chrome DevTools Protocol enabled.
#
# The MCP server attaches to TradingView over CDP, and CDP can only be enabled
# at launch time — so TradingView must be started by this script (or with the
# same flag) rather than from the dock/menu.
#
# Usage: ./scripts/launch-tradingview-debug.sh [port] [--force]
#   port     CDP port (default 9222)
#   --force  restart TradingView without asking if it is already running

set -euo pipefail

PORT=9222
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    ''|*[!0-9]*) ;;
    *) PORT="$arg" ;;
  esac
done

info()  { printf '\033[0;34m•\033[0m %s\n' "$1"; }
ok()    { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
warn()  { printf '\033[0;33m!\033[0m %s\n' "$1"; }
die()   { printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

cdp_up() { curl -sf -m 2 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; }

# Confirm the thing answering on $PORT is TradingView and not some other
# Chromium/Electron app that happened to claim it first.
cdp_is_tradingview() {
  curl -sf -m 2 "http://127.0.0.1:${PORT}/json/version" 2>/dev/null | grep -qi "tradingview"
}

# ── Already listening? Nothing to do. ────────────────────────────────────────
if cdp_up; then
  if cdp_is_tradingview; then
    ok "TradingView is already exposing CDP on port ${PORT}."
    exit 0
  fi
  die "Port ${PORT} is serving CDP, but it is not TradingView — another
    Chromium-based app owns it. Quit that app, or use another port: $0 9333"
fi

# ── Locate the app ───────────────────────────────────────────────────────────
OS="$(uname -s)"
TV_BIN=""

case "$OS" in
  Darwin)
    for candidate in \
      "/Applications/TradingView.app/Contents/MacOS/TradingView" \
      "$HOME/Applications/TradingView.app/Contents/MacOS/TradingView"; do
      [ -x "$candidate" ] && { TV_BIN="$candidate"; break; }
    done
    if [ -z "$TV_BIN" ] && command -v mdfind >/dev/null 2>&1; then
      app="$(mdfind "kMDItemCFBundleIdentifier == '*TradingView*'" 2>/dev/null | head -n1 || true)"
      [ -n "$app" ] && [ -x "$app/Contents/MacOS/TradingView" ] && TV_BIN="$app/Contents/MacOS/TradingView"
    fi
    ;;
  Linux)
    for candidate in \
      "$(command -v tradingview 2>/dev/null || true)" \
      "/opt/TradingView/tradingview" \
      "/usr/bin/tradingview" \
      "/usr/share/tradingview/tradingview"; do
      [ -n "$candidate" ] && [ -x "$candidate" ] && { TV_BIN="$candidate"; break; }
    done
    ;;
  *)
    die "Unsupported OS '$OS'. On Windows use scripts\\launch-tradingview-debug.bat instead."
    ;;
esac

[ -n "$TV_BIN" ] || die "Could not find the TradingView desktop app. Install it, or launch it manually:
    /path/to/TradingView --remote-debugging-port=${PORT}"

# ── Restart any running instance (CDP only attaches at launch) ───────────────
#
# Matching on the resolved binary path rather than the bare string "TradingView"
# keeps pkill from catching unrelated processes that merely mention the name.
tv_running() { pgrep -f "$TV_BIN" >/dev/null 2>&1; }

# Returns 0 once no TradingView process remains, 1 if still alive after $1 seconds.
wait_until_gone() {
  local seconds="$1"
  for _ in $(seq 1 "$seconds"); do
    tv_running || return 0
    sleep 1
  done
  return 1
}

if tv_running; then
  if [ "$FORCE" -eq 0 ]; then
    warn "TradingView is running without CDP enabled and must be restarted."
    read -r -p "  Quit and relaunch it now? [y/N] " reply
    case "$reply" in
      [yY]*) ;;
      *) die "Aborted. Quit TradingView yourself, then re-run this script." ;;
    esac
  fi

  info "Stopping the running TradingView instance…"
  pkill -f "$TV_BIN" 2>/dev/null || true

  # TradingView traps SIGTERM, so a polite kill can leave the process — and its
  # single-instance lock — alive. That lock then reaps the new instance we launch
  # with --remote-debugging-port, and the port dies moments after first
  # answering. Escalate to SIGKILL, which the app cannot trap.
  # See tradesdontlie/tradingview-mcp issue #186.
  if ! wait_until_gone 5; then
    info "Still running after SIGTERM — escalating to SIGKILL…"
    pkill -9 -f "$TV_BIN" 2>/dev/null || true
    wait_until_gone 5 || die "Could not stop TradingView. Quit it manually, then re-run."
  fi
fi

# ── Launch ───────────────────────────────────────────────────────────────────
info "Launching TradingView with --remote-debugging-port=${PORT}…"
nohup "$TV_BIN" --remote-debugging-port="$PORT" >/dev/null 2>&1 &
TV_PID=$!
disown "$TV_PID" 2>/dev/null || true

for _ in $(seq 1 20); do
  if cdp_up; then
    # A surviving old instance can reap this one a beat after the port first
    # answers, so re-check before declaring success rather than reporting a
    # connection that is already gone.
    sleep 2
    if cdp_up; then
      ok "TradingView is up on CDP port ${PORT} (pid ${TV_PID})."
      info "Leave this app running, then use the tradingview MCP tools from Claude Code."
      exit 0
    fi
    die "Port ${PORT} answered, then went dead — an older TradingView instance
    reaped the debug instance. Quit TradingView completely (or re-run with
    --force) and try again."
  fi
  sleep 1
done

die "TradingView started (pid ${TV_PID}) but port ${PORT} never answered.
    Make sure you are signed in, then re-run. If the port is taken, pass another: $0 9333"
