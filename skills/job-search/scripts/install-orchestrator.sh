#!/usr/bin/env bash
# Installs (or removes) the job-search orchestrator systemd user timers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC_DIR="$SCRIPT_DIR/../assets/systemd"
UNIT_DEST_DIR="$HOME/.config/systemd/user"

UNITS=(
  job-search-discover.service
  job-search-discover.timer
  job-search-liveness.service
  job-search-liveness.timer
  job-search-northbay.service
  job-search-northbay.timer
)

uninstall() {
  echo "Disabling timers..."
  systemctl --user disable --now job-search-discover.timer job-search-liveness.timer job-search-northbay.timer || true

  echo "Removing unit files..."
  for unit in "${UNITS[@]}"; do
    rm -f "$UNIT_DEST_DIR/$unit"
  done

  systemctl --user daemon-reload
  echo "Uninstalled."
  exit 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
fi

mkdir -p "$UNIT_DEST_DIR"

echo "Installing unit files to $UNIT_DEST_DIR..."
for unit in "${UNITS[@]}"; do
  cp "$UNIT_SRC_DIR/$unit" "$UNIT_DEST_DIR/$unit"
done

systemctl --user daemon-reload
systemctl --user enable --now job-search-discover.timer job-search-liveness.timer job-search-northbay.timer

echo
echo "Installed. Current timers:"
systemctl --user list-timers 'job-search-*'

echo
echo "NOTE: these timers only fire while you have an active login session."
echo "To let them run when you're logged out (e.g. after reboot with no session), run:"
echo "  loginctl enable-linger \$USER"
