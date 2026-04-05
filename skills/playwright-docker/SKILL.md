---
name: playwright-docker
description: >
  Dockerized Playwright + noVNC browser automation. Manages headless Chromium in Docker
  with file upload support and MCP integration. Supports hybrid golden/isolated sessions:
  golden session maintains persistent logins, isolated sessions use exported auth state.
  Triggers on: "playwright setup", "playwright start", "playwright stop", "playwright status",
  "browser docker", "start browser", "browser automation setup", "golden session", "golden open",
  "golden export".
---

# Playwright Docker Skill

Manages a Dockerized Playwright + noVNC browser for Claude Code automation. Built on
[xtr-dev/mcp-playwright-novnc](https://github.com/xtr-dev/mcp-playwright-novnc) (git
submodule) with minimal modifications for Claude Code compatibility.

**Assets location**: `~/workspace/agent-tools/skills/playwright-docker/assets/`

## Architecture

### Hybrid Golden + Isolated Sessions

Two MCP servers run in the same container on different ports:

| | Isolated (default) | Golden |
|---|---|---|
| **Port** | 3080 | 3081 |
| **Mode** | `--isolated` (ephemeral) | `--cdp-endpoint` → persistent Chromium |
| **Auth** | Loaded from exported storage state | Maintained via noVNC login |
| **Parallelism** | Fully parallelizable | Single-client only |
| **Use case** | All agent work (scraping, form filling) | Logging into sites, maintaining sessions |

**Flow**: User logs into sites via golden session (noVNC) → export storage state → isolated sessions automatically load cookies.

### Components

- **Docker container** (`playwright-display`): Runs persistent golden Chromium + two Playwright MCP servers + noVNC
- **MCP connection**: Claude Code connects via `mcp__playwright__` tools (stdio → SSE proxy)
- **noVNC**: http://localhost:6080/vnc.html — watch or manually interact with the browser
- **Golden session** (port 3081): Persistent browser profile for logins
- **Isolated sessions** (port 3080): Ephemeral browsers pre-loaded with exported auth state

### Upstream modifications

The upstream source lives in `assets/mcp-playwright-novnc/` as a **git submodule**. We
overlay changes without modifying it:

1. **`--output-dir /tmp/.playwright-mcp`** (in `start-mcp.sh`) — Claude Code sends MCP
   `roots` with host paths that don't exist in the container (EACCES workaround).
2. **Local image build** — upstream GHCR package is private/unavailable.
3. **Custom `supervisord.conf`** — adds golden browser + golden MCP server processes.
4. **`start-golden-browser.sh`** — launches persistent Chromium with `--user-data-dir` and CDP on port 9222.
5. **`start-mcp-golden.sh`** — golden MCP server that connects to golden Chromium via `--cdp-endpoint`.
6. **`export-storage-state.js`** — exports auth state from golden browser via Playwright CDP.
7. **Custom `entrypoint.sh`** — fixes Docker volume ownership before starting supervisord.

## Prerequisites

Before any sub-command, ensure the submodule is initialized and the image exists:

```bash
# Initialize submodule (no-op if already present)
cd ~/workspace/agent-tools
git submodule update --init skills/playwright-docker/assets/mcp-playwright-novnc

# Build image (uses cache if unchanged, safe to run repeatedly)
export RESUME_REPO_PATH=~/workspace/resume
cd ~/workspace/agent-tools/skills/playwright-docker/assets
docker compose build
```

## Sub-Commands

### `setup` — First-time setup

Run once to start the container and wire up the MCP server in Claude Code.

#### 1. Build and start the container

```bash
cd ~/workspace/agent-tools
git submodule update --init skills/playwright-docker/assets/mcp-playwright-novnc

export RESUME_REPO_PATH=~/workspace/resume
cd ~/workspace/agent-tools/skills/playwright-docker/assets
docker compose up -d --build
```

Verify it's running:
```bash
docker ps | grep playwright-display
```

noVNC is at http://localhost:6080/vnc.html. The browser itself does not launch until the
first MCP tool call.

#### 2. Add the MCP server (user-scoped, persists across all projects)

Check if already configured:
```bash
grep -q playwright ~/.claude.json && echo "already configured"
```

If not, add the isolated session MCP server (default for all agent work):
```bash
claude mcp add --scope user playwright -- docker run --rm -i --network=playwright-network mcp-playwright-novnc:local mcp-proxy http://playwright-display:3080/sse
```

Tools will be available as `mcp__playwright__browser_*`.

#### 3. Verify

Call `mcp__playwright__browser_navigate` to `https://google.com` and confirm
`mcp__playwright__browser_snapshot` returns content.

---

### `golden open` — Start using the golden session

The golden session runs automatically alongside the isolated server. To interact with it:

1. Open noVNC at http://localhost:6080/vnc.html
2. The golden browser launches on the first MCP connection to port 3081

To connect Claude Code to the golden session (for explicit automation):
```bash
claude mcp add --scope user playwright-golden -- docker run --rm -i --network=playwright-network mcp-playwright-novnc:local mcp-proxy http://playwright-display:3081/sse
```

Tools are then available as `mcp__playwright-golden__browser_*`.

**Important**: Only one client should use the golden session at a time (user via noVNC
or Claude Code, not both simultaneously).

### `golden export` — Export auth state to isolated sessions

After logging into sites in the golden session, export cookies and localStorage:

```bash
docker exec -e NODE_PATH=/app/node_modules playwright-display node /usr/local/bin/export-storage-state.js /home/pwuser/state/storage-state.json
```

This writes a Playwright storage state file that isolated sessions load automatically.
After exporting, new isolated MCP connections will pick up the auth state. Existing
connections keep their current state (reconnect via `/mcp` or new conversation to refresh).

To verify the export:
```bash
docker exec playwright-display cat /home/pwuser/state/storage-state.json | python3 -m json.tool | head -20
```

### `golden close` — Remove golden MCP server from Claude Code

If you no longer need direct automation of the golden session:
```bash
claude mcp remove playwright-golden
```

The golden browser process continues running in the container (logins persist).

---

### `start` — Start the container

```bash
export RESUME_REPO_PATH=~/workspace/resume
cd ~/workspace/agent-tools/skills/playwright-docker/assets
docker compose up -d --build
```

### `stop` — Stop the container

```bash
cd ~/workspace/agent-tools/skills/playwright-docker/assets
docker compose down
```

### `restart` — Restart the container

```bash
cd ~/workspace/agent-tools/skills/playwright-docker/assets
docker compose restart
```

**Important**: After any restart, the MCP proxy holds a stale session ID. Either start a
new Claude Code conversation or run `/mcp` to reconnect.

### `status` — Check health

```bash
docker ps --filter name=playwright-display --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Check both MCP servers are responding:
```bash
# Isolated (3080)
curl -s http://localhost:3080/sse -o /dev/null -w "%{http_code}"
# Golden (3081)
curl -s http://localhost:3081/sse -o /dev/null -w "%{http_code}"
```

Also confirm MCP connectivity: `mcp__playwright__browser_navigate` to `https://google.com`.

### `update` — Pull upstream changes

```bash
cd ~/workspace/agent-tools
git submodule update --remote skills/playwright-docker/assets/mcp-playwright-novnc

export RESUME_REPO_PATH=~/workspace/resume
cd ~/workspace/agent-tools/skills/playwright-docker/assets
docker compose up -d --build
```

This pulls the latest upstream commit, rebuilds the image, and restarts the container.
After updating, reconnect the MCP server (new conversation or `/mcp`).

---

## Troubleshooting

### `MCP error -32603: HTTP 404: Session not found`

The MCP proxy has a stale session from before a container restart. Fix: start a new
conversation or run `/mcp` to reconnect. If that doesn't work, kill the stale proxy:

```bash
docker ps --filter "ancestor=mcp-playwright-novnc:local" --format "{{.ID}} {{.Command}}" | grep "mcp-" | awk '{print $1}' | xargs -r docker kill
```

Then reconnect via `/mcp`.

### `mcp__playwright__` tools not available

The MCP server isn't connected. Check:
1. Container running? `docker ps | grep playwright-display`
2. MCP configured? `grep playwright ~/.claude.json`
3. If both yes, run `/mcp` to reconnect.

### `EACCES: permission denied, mkdir`

The `--output-dir` workaround isn't active. Check that `start-mcp.sh` is mounted:
```bash
docker exec playwright-display cat /usr/local/bin/start-mcp.sh | grep output-dir
```

### Golden session: "browser already in use" lock error

Only one client can connect to the golden session at a time. Check for stale proxy
containers connected to port 3081:
```bash
docker ps --filter "ancestor=mcp-playwright-novnc:local" --format "{{.ID}} {{.Command}}" | grep 3081 | awk '{print $1}' | xargs -r docker kill
```

### Storage state not loading in isolated sessions

1. Check the file exists: `docker exec playwright-display ls -la /home/pwuser/state/storage-state.json`
2. Check start-mcp.sh sees it: `docker exec playwright-display cat /usr/local/bin/start-mcp.sh`
3. Reconnect MCP (`/mcp`) — storage state is loaded at connection time, not dynamically.

---

## Using the Browser Tools

Once set up, use `mcp__playwright__` tools in any skill or task:

| Tool | Purpose |
|------|---------|
| `mcp__playwright__browser_navigate` | Go to a URL |
| `mcp__playwright__browser_snapshot` | Capture accessibility tree (primary scraping method) |
| `mcp__playwright__browser_click` | Click an element |
| `mcp__playwright__browser_type` | Type into a field |
| `mcp__playwright__browser_press_key` | Press a key (Enter, ArrowDown, Tab, etc.) |
| `mcp__playwright__browser_select_option` | Select from standard `<select>` dropdown |
| `mcp__playwright__browser_file_upload` | Upload a file programmatically |
| `mcp__playwright__browser_take_screenshot` | Capture a screenshot |
| `mcp__playwright__browser_wait_for` | Wait for an element or condition |
| `mcp__playwright__browser_hover` | Hover over an element |

### File uploads

Use `browser_file_upload` with the container-internal path. The resume repo is mounted at
`/home/pwuser/resume/` (read-only), so for resume uploads:

```
/home/pwuser/resume/resume.pdf
```

### Form-filling gotchas

- **Lever combobox dropdowns**: Don't work with `browser_select_option`. Use click → `ArrowDown` → `Enter`.
- **Standard HTML `<select>`** (e.g., EEO fields): Use `browser_select_option` normally.
- **Location autocomplete**: Type city name only (e.g., "Portland"), wait for suggestions, `ArrowDown` + `Enter`.
- **Stale refs**: After each `browser_type` or `browser_click`, refs update. Always use refs from the most recent snapshot.

---

## Container Lifecycle

The container is configured with `restart: unless-stopped`, so it survives reboots.
The golden session's browser profile persists across restarts via a Docker named volume.

```bash
cd ~/workspace/agent-tools/skills/playwright-docker/assets

docker compose up -d --build  # Start/rebuild
docker compose restart        # Restart (reconnect MCP after)
docker compose down           # Stop (golden profile preserved)
docker compose down -v        # Stop and delete golden profile + storage state
```

---

## Requirements

- Docker and Docker Compose
- ~3GB disk for the locally-built image
- ~1GB RAM while running (+ ~500MB for golden session browser)
- Ports 6080 (noVNC), 3080 (isolated MCP), and 3081 (golden MCP) available locally
