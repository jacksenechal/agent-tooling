#!/bin/bash
set -e

# Launch a persistent Chromium for the golden session.
# MCP server connects to it via CDP (--cdp-endpoint).
# This decouples browser lifecycle from MCP connections — reconnections
# just re-attach to the same running browser, no lock issues.

GOLDEN_PROFILE="/home/pwuser/golden-profile"
CDP_PORT="${GOLDEN_CDP_PORT:-9222}"

mkdir -p "$GOLDEN_PROFILE"

# Wait for X11
sleep 3

# Find the newest Chromium binary installed by Playwright
CHROME_BIN=$(find /ms-playwright -name "chrome" -path "*/chrome-linux64/*" | sort -V | tail -1)
if [ -z "$CHROME_BIN" ]; then
    echo "ERROR: No Chromium binary found in /ms-playwright"
    exit 1
fi

echo "Starting golden Chromium..."
echo "  Binary: ${CHROME_BIN}"
echo "  Profile: ${GOLDEN_PROFILE}"
echo "  CDP port: ${CDP_PORT}"
echo "  Display: ${DISPLAY:-:99}"

exec "$CHROME_BIN" \
    --no-sandbox \
    --disable-dev-shm-usage \
    --user-data-dir="$GOLDEN_PROFILE" \
    --remote-debugging-port="$CDP_PORT" \
    --remote-debugging-address=0.0.0.0 \
    --no-first-run \
    --no-default-browser-check \
    --window-size=1920,1080 \
    about:blank
