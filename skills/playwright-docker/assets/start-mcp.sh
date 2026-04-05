#!/bin/bash
set -e

# Isolated session: ephemeral browser for agent work.
# Pre-loads auth cookies from storage state if available.

# Wait for X11 to be ready
sleep 2

# Calculate viewport size
VIEWPORT_WIDTH=$((${SCREEN_WIDTH:-1920} - 0))
VIEWPORT_HEIGHT=$((${SCREEN_HEIGHT:-1080} - 0))

# Check for exported storage state from golden session
STORAGE_STATE="${STORAGE_STATE_PATH:-/home/pwuser/state/storage-state.json}"
STORAGE_STATE_ARGS=""
if [ -f "$STORAGE_STATE" ]; then
    echo "Loading storage state from golden session: ${STORAGE_STATE}"
    STORAGE_STATE_ARGS="--storage-state ${STORAGE_STATE}"
fi

echo "Starting Playwright MCP server (isolated)..."
echo "  Port: ${MCP_PORT:-3000}"
echo "  Browser: ${MCP_BROWSER:-chromium}"
echo "  Display: ${DISPLAY:-:99}"
echo "  Viewport: ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}"
echo "  Storage state: ${STORAGE_STATE_ARGS:-none}"

# --output-dir: Claude Code sends MCP roots with host filesystem paths that
# don't exist inside the container. Without this flag the server tries to mkdir
# at those paths and fails with EACCES. This overrides that behavior.
# See: https://github.com/microsoft/playwright-mcp/issues/1240#issuecomment-2888187192
# shellcheck disable=SC2086
exec node /app/cli.js \
    --port "${MCP_PORT:-3000}" \
    --host 0.0.0.0 \
    --browser "${MCP_BROWSER:-chromium}" \
    --config /etc/playwright-config.json \
    --allowed-hosts "*" \
    --viewport-size "${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}" \
    --output-dir /tmp/.playwright-mcp \
    --isolated \
    $STORAGE_STATE_ARGS
