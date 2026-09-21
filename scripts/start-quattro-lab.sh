#!/bin/sh
# Start the reversible Quattro lab session from the Jetson's physical TTY.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE_DIR="$ROOT_DIR/artifacts/quattro-runs"
ARCHIVE_STAMP=$(date +%Y%m%d-%H%M%S)
RUN_STAMP=
SESSION_BACKEND=${QUATTRO_SESSION_BACKEND:-lab-vt}
. "$SCRIPT_DIR/quattro-session-common.sh"
quattro_require_backend "$SESSION_BACKEND" lab-vt

quattro_docker() {
  sudo docker "$@"
}

usage() {
  echo "Usage: $0 [--check]" >&2
  exit 2
}

CHECK_ONLY=0
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  *) usage ;;
esac

# Validate the physical-console requirement before archiving anything. This is
# especially important for --check: an SSH invocation should fail cleanly and
# leave the previous stopped containers untouched.
START_TTY=${SUDO_TTY:-$(tty 2>/dev/null || true)}
case "${START_TTY#/dev/tty}" in
  ''|0|*[!0-9]*)
    echo "A physical VT is required before the launcher can archive or start a run (detected: ${START_TTY:-none})." >&2
    echo "Run it from the Jetson's local text console, or use the SSH-safe health report." >&2
    exit 1 ;;
esac

"$SCRIPT_DIR/check-syntax.sh"

quattro_archive_stopped_container quickshell-quattro-smoke "$ARCHIVE_DIR" "$ARCHIVE_STAMP"
quattro_archive_stopped_container hyprland-phase2-drm "$ARCHIVE_DIR" "$ARCHIVE_STAMP"
RUN_STAMP=$(quattro_new_run_id)

if [ "$CHECK_ONLY" -eq 1 ]; then
  exec env QUATTRO_RUN_ID="$RUN_STAMP" QUATTRO_SESSION_BACKEND="$SESSION_BACKEND" "$SCRIPT_DIR/run-hyprland-drm.sh" --stop-gdm --quattro --check
fi

echo "Starting Quattro lab session. Exit with Super+Shift+E; GDM will return."
exec env QUATTRO_RUN_ID="$RUN_STAMP" QUATTRO_SESSION_BACKEND="$SESSION_BACKEND" "$SCRIPT_DIR/run-hyprland-drm.sh" --stop-gdm --quattro
