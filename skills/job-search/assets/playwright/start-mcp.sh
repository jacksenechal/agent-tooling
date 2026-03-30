#!/bin/bash
set -e

# Wait for X11 to be ready
sleep 2

# Forcefully kill any remaining browser processes from previous runs in this container
# (They might be orphans if the server process crashed or was killed)
for pid_exe in /proc/[0-9]*/exe; do
    if ls -l "$pid_exe" 2>/dev/null | grep -q "chrome\|chromium"; then
        target_pid=$(echo "$pid_exe" | cut -d/ -f3)
        echo "Cleaning up stale browser process: $target_pid"
        kill -9 "$target_pid" 2>/dev/null || true
    fi
done

# Profile directory mapped to a Docker volume
USER_DATA_DIR="/home/pwuser/persistent-profile"
mkdir -p "$USER_DATA_DIR"

# Clean stale Chromium lock files from previous container runs.
# These can block Chromium from starting if the container was not shut down gracefully.
rm -f "$USER_DATA_DIR/SingletonLock" \
      "$USER_DATA_DIR/SingletonCookie" \
      "$USER_DATA_DIR/SingletonSocket" 2>/dev/null || true

VIEWPORT_WIDTH=$((${SCREEN_WIDTH:-1920} - 0))
VIEWPORT_HEIGHT=$((${SCREEN_HEIGHT:-1080} - 0))

echo "Starting Playwright MCP server..."
echo "  Port: ${MCP_PORT:-3000}"
echo "  Browser: ${MCP_BROWSER:-chromium}"
echo "  Display: ${DISPLAY:-:99}"
echo "  Viewport: ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}"
echo "  User Data Dir: $USER_DATA_DIR"

# --user-data-dir: persistent profile (LinkedIn sessions survive restarts)
# --shared-browser-context: all SSE clients share one browser instance
# No --isolated: enables persistence to disk
exec node /app/cli.js \
    --host 0.0.0.0 \
    --port "${MCP_PORT:-3000}" \
    --browser "${MCP_BROWSER:-chromium}" \
    --config /etc/playwright-config.json \
    --allowed-hosts "*" \
    --viewport-size "${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT}" \
    --user-data-dir "$USER_DATA_DIR" \
    --shared-browser-context
