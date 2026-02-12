#!/bin/sh
set -e

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

  # Write managed openclaw.json on every start so config updates
  # propagate on redeploy without needing to delete the volume.
  # OpenClaw supports ${VAR} substitution in config values, so secrets
  # are read from environment variables at runtime.
  if [ -n "${OPENCLAW_STATE_DIR:-}" ]; then
    # Write MCP config with Luciq server (shell expands env vars here)
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

    # Write openclaw.json (single-quoted SEED = no shell expansion;
    # openclaw's own ${VAR} substitution handles env refs at load time)
    _cfg="$OPENCLAW_STATE_DIR/openclaw.json"
    cat > "$_cfg" <<'SEED'
{
  "gateway": {
    "trustedProxies": ["100.64.0.0/10"],
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "claude-cli/claude-sonnet-4-5"
      },
      "cliBackends": {
        "claude-cli": {
          "command": "claude",
          "args": [
            "-p",
            "--output-format", "json",
            "--dangerously-skip-permissions",
            "--mcp-config", "/data/.openclaw/mcp.json"
          ],
          "output": "json",
          "input": "arg",
          "modelArg": "--model",
          "sessionArg": "--session-id",
          "sessionMode": "always",
          "systemPromptArg": "--append-system-prompt",
          "systemPromptMode": "append",
          "systemPromptWhen": "first",
          "serialize": true
        }
      }
    },
    "list": [
      {
        "id": "main"
      }
    ]
  }
}
SEED
    chown node:node "$_cfg"
  fi

  exec gosu node "$@"
fi

# Already running as non-root (e.g. docker-compose with USER override)
exec "$@"
