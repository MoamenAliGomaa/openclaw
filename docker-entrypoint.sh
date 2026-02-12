#!/bin/sh
set -e

echo "[entrypoint] uid=$(id -u) user=$(whoami)"

# ── Always write config to /tmp (writable by any user, never shadowed by volumes) ──
cat > /tmp/openclaw-config.json <<'OCCONFIG'
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
            "--mcp-config", "/tmp/openclaw-mcp.json"
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
OCCONFIG
echo "[entrypoint] wrote config to /tmp/openclaw-config.json"
export OPENCLAW_CONFIG_PATH=/tmp/openclaw-config.json

# ── Write MCP config (shell expands env vars for credentials) ──
cat > /tmp/openclaw-mcp.json <<MCP
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
echo "[entrypoint] wrote MCP config to /tmp/openclaw-mcp.json"

# ── Root-only setup: create data dirs and drop to node user ──
if [ "$(id -u)" = '0' ]; then
  if [ -n "${OPENCLAW_STATE_DIR:-}" ]; then
    mkdir -p "$OPENCLAW_STATE_DIR"
    chown node:node "$OPENCLAW_STATE_DIR"
  fi
  if [ -n "${OPENCLAW_WORKSPACE_DIR:-}" ]; then
    mkdir -p "$OPENCLAW_WORKSPACE_DIR"
    chown node:node "$OPENCLAW_WORKSPACE_DIR"
  fi
  if [ -d /data ]; then
    chown node:node /data 2>/dev/null || true
  fi

  echo "[entrypoint] dropping to node user via gosu"
  exec gosu node "$@"
fi

# Already running as non-root
exec "$@"
