#!/bin/sh
# Start the reversible Quattro lab session from the Jetson's physical TTY.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE_DIR="$ROOT_DIR/artifacts/quattro-runs"
RUN_STAMP=$(date +%Y%m%d-%H%M%S)

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

archive_stopped_container() {
  name=$1
  sudo docker container inspect "$name" >/dev/null 2>&1 || return 0
  state=$(sudo docker container inspect -f '{{.State.Status}}' "$name")
  if [ "$state" != exited ]; then
    echo "Container $name is $state; stop it or use its existing session first." >&2
    exit 1
  fi
  install -d -m 0755 "$ARCHIVE_DIR/$RUN_STAMP"
  sudo docker logs "$name" >"$ARCHIVE_DIR/$RUN_STAMP/$name.log" 2>&1 || true
  sudo docker inspect "$name" >"$ARCHIVE_DIR/$RUN_STAMP/$name.inspect.json"
  sudo docker rm "$name" >/dev/null
  echo "Archived completed $name logs in artifacts/quattro-runs/$RUN_STAMP"
}

archive_stopped_container quickshell-quattro-smoke
archive_stopped_container hyprland-phase2-drm

if [ "$CHECK_ONLY" -eq 1 ]; then
  exec "$SCRIPT_DIR/run-hyprland-drm.sh" --stop-gdm --quattro --check
fi

echo "Starting Quattro lab session. Exit with Super+Shift+E; GDM will return."
exec "$SCRIPT_DIR/run-hyprland-drm.sh" --stop-gdm --quattro
