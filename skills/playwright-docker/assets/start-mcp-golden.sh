#!/bin/bash
set -e

# Golden MCP server: connects to the persistent golden Chromium via CDP.
# The browser runs separately (start-golden-browser.sh), so MCP reconnections
# just re-attach — no profile locks, no lost sessions.

# Wait for X11 + golden browser to be ready
sleep 5

GOLDEN_PORT="${GOLDEN_MCP_PORT:-3081}"
CDP_PORT="${GOLDEN_CDP_PORT:-9222}"
VIEWPORT_WIDTH=$((${SCREEN_WIDTH:-1920} - 0))
VIEWPORT_HEIGHT=$((${SCREEN_HEIGHT:-1080} - 0))

# Wait for CDP to be available
echo "Waiting for golden Chromium CDP on port ${CDP_PORT}..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:${CDP_PORT}/json/version" > /dev/null 2>&1; then
        echo "  CDP ready after ${i}s"
        break
    fi
    sleep 1
done

echo "Starting Golden MCP server..."
echo "  Port: ${GOLDEN_PORT}"
echo "  CDP endpoint: http://localhost:${CDP_PORT}"
echo "  Viewport: ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}"

exec node /app/cli.js \
    --port "${GOLDEN_PORT}" \
    --host 0.0.0.0 \
    --cdp-endpoint "http://localhost:${CDP_PORT}" \
    --allowed-hosts "*" \
    --viewport-size "${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}" \
    --output-dir /tmp/.playwright-mcp-golden \
    --shared-browser-context
