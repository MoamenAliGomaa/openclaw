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

  # Write gateway config to trust Railway/Render/Fly reverse proxies
  # and disable device pairing for the Control UI.
  if [ -n "${OPENCLAW_STATE_DIR:-}" ]; then
    _cfg="$OPENCLAW_STATE_DIR/openclaw.json"
    cat > "$_cfg" <<'SEED'
{
  "gateway": {
    "trustedProxies": ["100.64.0.0/10"],
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
SEED
    chown node:node "$_cfg"
  fi

  exec gosu node "$@"
fi

# Already running as non-root (e.g. docker-compose with USER override)
exec "$@"
