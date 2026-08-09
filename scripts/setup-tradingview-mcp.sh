#!/usr/bin/env bash
# One-time setup: install the TradingView MCP server and register it with
# Claude Code for this project.
#
# Run this on your own machine (the one with the TradingView desktop app) —
# not in a remote/cloud Claude Code session, which has no access to it.
#
# Usage: ./scripts/setup-tradingview-mcp.sh
# Env:   TRADINGVIEW_MCP_HOME  where to install (default ~/tools/tradingview-mcp)

set -euo pipefail

REPO_URL="https://github.com/tradesdontlie/tradingview-mcp.git"
INSTALL_DIR="${TRADINGVIEW_MCP_HOME:-$HOME/tools/tradingview-mcp}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '\033[0;34m•\033[0m %s\n' "$1"; }
ok()   { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
die()  { printf '\033[0;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# ── Prerequisites ────────────────────────────────────────────────────────────
command -v git  >/dev/null 2>&1 || die "git is required but not installed."
command -v node >/dev/null 2>&1 || die "Node.js 18+ is required but not installed."
command -v npm  >/dev/null 2>&1 || die "npm is required but not installed."

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "Node.js 18+ required (found $(node -v))."

# ── Install / update the MCP server ──────────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
  info "Updating existing install at $INSTALL_DIR…"
  git -C "$INSTALL_DIR" pull --ff-only
else
  info "Cloning tradingview-mcp into $INSTALL_DIR…"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

info "Installing dependencies…"
npm --prefix "$INSTALL_DIR" install

SERVER_JS="$INSTALL_DIR/src/server.js"
[ -f "$SERVER_JS" ] || die "Expected server entrypoint not found at $SERVER_JS.
    The upstream layout may have changed — check $INSTALL_DIR/README.md."

# ── Register with Claude Code (project scope) ────────────────────────────────
MCP_JSON="$PROJECT_DIR/.mcp.json"

if command -v claude >/dev/null 2>&1; then
  info "Registering the 'tradingview' MCP server with Claude Code…"
  claude mcp remove tradingview --scope project >/dev/null 2>&1 || true
  claude mcp add tradingview --scope project -- node "$SERVER_JS"
else
  info "Claude CLI not on PATH — writing $MCP_JSON directly…"
  [ -f "$MCP_JSON" ] && cp "$MCP_JSON" "$MCP_JSON.bak" && info "Backed up existing config to .mcp.json.bak"
  cat > "$MCP_JSON" <<EOF
{
  "mcpServers": {
    "tradingview": {
      "command": "node",
      "args": ["$SERVER_JS"]
    }
  }
}
EOF
fi

chmod +x "$PROJECT_DIR/scripts/launch-tradingview-debug.sh" 2>/dev/null || true

ok "Setup complete."
cat <<EOF

Next steps:
  1. Start TradingView with debugging enabled:
       ./scripts/launch-tradingview-debug.sh
  2. Open this project in Claude Code Desktop and approve the project-scoped
     MCP server when prompted (or run: claude mcp list).
  3. Verify the connection by asking Claude:
       "Use tv_health_check to verify TradingView is connected"

Details and troubleshooting: docs/tradingview-desktop-setup.md
EOF
