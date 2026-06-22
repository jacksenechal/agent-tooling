#!/usr/bin/env bash
#
# Lifecycle manager for the job-search ArcadeDB knowledge graph.
#
# The graph DB holds a ~2GB JVM heap and is only needed while actively
# querying/ingesting. This script starts it on demand, records a heartbeat on
# each use, and (via a self-installed systemd user timer) stops it once it has
# been idle past JOB_SEARCH_ARCADEDB_IDLE seconds. Decoupled from Claude: it
# reaps the container no matter who started it.
#
# Subcommands:
#   ensure         Start the container if needed, wait until ready, touch heartbeat,
#                  and make sure the idle-reaper timer is installed. Call this before
#                  any query/ingest.
#   touch          Update the heartbeat (extends the idle window).
#   reap           Stop the container if idle past the threshold. Run by the timer.
#   stop           Stop the container now.
#   status         Show container + heartbeat + timer state.
#   install-timer  Install/enable the systemd user timer (idempotent).
#
set -euo pipefail

CONTAINER="${JOB_SEARCH_ARCADEDB_CONTAINER:-arcadedb}"
IDLE_SECONDS="${JOB_SEARCH_ARCADEDB_IDLE:-10800}"   # 3 hours
ARCADE_PORT="${ARCADE_PORT:-2480}"
ARCADE_USER="${ARCADE_USER:-root}"
ARCADE_PASS="${ARCADE_PASS:-playwithdata}"

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/arcadedb" && pwd)"
HEARTBEAT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/job-search"
HEARTBEAT_FILE="$HEARTBEAT_DIR/arcadedb-last-use"

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_UNIT="job-search-arcadedb-reap.service"
TIMER_UNIT="job-search-arcadedb-reap.timer"

log() { printf '[arcadedb_ctl] %s\n' "$*" >&2; }

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]
}

container_exists() {
  docker inspect "$CONTAINER" >/dev/null 2>&1
}

touch_heartbeat() {
  mkdir -p "$HEARTBEAT_DIR"
  date +%s > "$HEARTBEAT_FILE"
}

wait_ready() {
  local url="http://localhost:${ARCADE_PORT}/api/v1/server"
  for _ in $(seq 1 30); do
    if curl -fsS -u "${ARCADE_USER}:${ARCADE_PASS}" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  log "WARNING: ArcadeDB did not become ready within 30s (continuing anyway)"
  return 0
}

cmd_ensure() {
  if container_running; then
    log "already running"
  elif container_exists; then
    log "starting existing container '$CONTAINER'"
    docker start "$CONTAINER" >/dev/null
    wait_ready
  else
    log "creating container via docker compose"
    ( cd "$COMPOSE_DIR" && docker compose up -d )
    wait_ready
  fi
  touch_heartbeat
  install_timer_quiet
}

cmd_touch() {
  touch_heartbeat
}

cmd_reap() {
  if ! container_running; then
    log "not running; nothing to reap"
    return 0
  fi
  if [ ! -f "$HEARTBEAT_FILE" ]; then
    # Running but never touched (e.g. started by hand). Start the idle clock now
    # so it gets a full grace window rather than being killed immediately.
    log "running with no heartbeat; starting idle clock"
    touch_heartbeat
    return 0
  fi
  local last now idle
  last="$(cat "$HEARTBEAT_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  idle=$(( now - last ))
  if [ "$idle" -ge "$IDLE_SECONDS" ]; then
    log "idle ${idle}s >= ${IDLE_SECONDS}s; stopping '$CONTAINER'"
    docker stop "$CONTAINER" >/dev/null
  else
    log "idle ${idle}s < ${IDLE_SECONDS}s; leaving running"
  fi
}

cmd_stop() {
  if container_running; then
    docker stop "$CONTAINER" >/dev/null
    log "stopped '$CONTAINER'"
  else
    log "not running"
  fi
}

cmd_status() {
  printf 'container : %s\n' "$(container_running && echo running || echo stopped)"
  if [ -f "$HEARTBEAT_FILE" ]; then
    local last now
    last="$(cat "$HEARTBEAT_FILE")"
    now="$(date +%s)"
    printf 'last use  : %s (%ss ago)\n' "$(date -d "@$last" 2>/dev/null || echo "$last")" "$(( now - last ))"
  else
    printf 'last use  : (no heartbeat)\n'
  fi
  printf 'idle limit: %ss\n' "$IDLE_SECONDS"
  printf 'timer     : %s\n' "$(systemctl --user is-active "$TIMER_UNIT" 2>/dev/null || echo inactive)"
}

write_units() {
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/$SERVICE_UNIT" <<EOF
[Unit]
Description=Stop the job-search ArcadeDB container when idle

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH reap
EOF
  cat > "$UNIT_DIR/$TIMER_UNIT" <<EOF
[Unit]
Description=Periodically reap the idle job-search ArcadeDB container

[Timer]
OnBootSec=15min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

install_timer_quiet() {
  # Reinstall only if the unit files are missing or stale, so `ensure` stays cheap.
  if [ ! -f "$UNIT_DIR/$TIMER_UNIT" ] || ! grep -q "ExecStart=$SCRIPT_PATH reap" "$UNIT_DIR/$SERVICE_UNIT" 2>/dev/null; then
    cmd_install_timer
  fi
}

cmd_install_timer() {
  write_units
  systemctl --user daemon-reload
  systemctl --user enable --now "$TIMER_UNIT" >/dev/null 2>&1 || systemctl --user enable --now "$TIMER_UNIT"
  log "installed and enabled $TIMER_UNIT"
}

case "${1:-}" in
  ensure)        cmd_ensure ;;
  touch)         cmd_touch ;;
  reap)          cmd_reap ;;
  stop)          cmd_stop ;;
  status)        cmd_status ;;
  install-timer) cmd_install_timer ;;
  *)
    echo "Usage: $0 {ensure|touch|reap|stop|status|install-timer}" >&2
    exit 1
    ;;
esac
