#!/bin/sh
set -e

echo "[entrypoint] uid=$(id -u) OPENCLAW_STATE_DIR=${OPENCLAW_STATE_DIR:-<unset>} OPENCLAW_CONFIG_PATH=${OPENCLAW_CONFIG_PATH:-<unset>}"

# When running as root (default in Docker), ensure data directories exist
# and are writable by the non-root node user, then re-exec as node.
# This is required on platforms like Railway/Render/Fly where volumes are
# mounted at runtime with root ownership.
if [ "$(id -u)" = '0' ]; then
  # Ensure OPENCLAW_STATE_DIR exists and is owned by node
  if [ -n "${OPENCLAW_STATE_DIR:-}" ]; then
    mkdir -p "$OPENCLAW_STATE_DIR"
    chown node:node "$OPENCLAW_STATE_DIR"
  fi

  # Ensure OPENCLAW_WORKSPACE_DIR exists and is owned by node
  if [ -n "${OPENCLAW_WORKSPACE_DIR:-}" ]; then
    mkdir -p "$OPENCLAW_WORKSPACE_DIR"
    chown node:node "$OPENCLAW_WORKSPACE_DIR"
  fi

  # Common volume mount point — ensure node can write to it
  if [ -d /data ]; then
    chown node:node /data 2>/dev/null || true
  fi

  # Write MCP config for Claude CLI (shell expands env vars here).
  # The main openclaw.json is baked into the image via OPENCLAW_CONFIG_PATH,
  # but mcp.json needs runtime env vars for credentials.
  if [ -n "${OPENCLAW_STATE_DIR:-}" ]; then
    _mcp="$OPENCLAW_STATE_DIR/mcp.json"
    cat > "$_mcp" <<MCP
{
  "mcpServers": {
    "luciq": {
      "url": "https://api.instabug.com/api/mcp",
      "headers": {
        "Email": "${INSTABUG_EMAIL:-}",
        "Token": "${INSTABUG_TOKEN:-}"
      }
    }
  }
}
MCP
    chown node:node "$_mcp"
    echo "[entrypoint] wrote MCP config to $_mcp"
  fi

  # Verify the baked-in config exists
  if [ -n "${OPENCLAW_CONFIG_PATH:-}" ]; then
    if [ -f "$OPENCLAW_CONFIG_PATH" ]; then
      echo "[entrypoint] config exists at $OPENCLAW_CONFIG_PATH"
    else
      echo "[entrypoint] WARNING: config NOT found at $OPENCLAW_CONFIG_PATH"
    fi
  fi

  echo "[entrypoint] dropping to node user via gosu"
  exec gosu node "$@"
fi

# Already running as non-root (e.g. docker-compose with USER override)
exec "$@"
