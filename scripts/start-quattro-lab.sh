#!/bin/sh
# Start the reversible Quattro lab session from the Jetson's physical TTY.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE_DIR="$ROOT_DIR/artifacts/quattro-runs"
ARCHIVE_STAMP=$(date +%Y%m%d-%H%M%S)
RUN_STAMP=

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
  container_run=$(sudo docker container inspect -f '{{index .Config.Labels "dev.omarchy-quattro.run-id"}}' "$name" 2>/dev/null || true)
  case "$container_run" in
    ''|*[!A-Za-z0-9_-]*) archive_run=$ARCHIVE_STAMP ;;
    *) archive_run=$container_run ;;
  esac
  install -d -m 0755 "$ARCHIVE_DIR/$archive_run"
  log_tmp="$ARCHIVE_DIR/$archive_run/.$name.log.$$"
  inspect_tmp="$ARCHIVE_DIR/$archive_run/.$name.inspect.json.$$"
  # A prior root cleanup may have created the destination files. Create fresh
  # user-owned files in the user-owned run directory, then atomically rename;
  # opening an existing root-owned destination for redirection would fail.
  if ! sudo docker logs "$name" >"$log_tmp" 2>&1; then
    printf '%s\n' "docker logs returned nonzero for $name; output retained." >>"$log_tmp"
  fi
  if ! sudo docker inspect "$name" >"$inspect_tmp"; then
    rm -f "$log_tmp" "$inspect_tmp"
    echo "Could not inspect stopped container $name; leaving it untouched." >&2
    exit 1
  fi
  mv -f "$log_tmp" "$ARCHIVE_DIR/$archive_run/$name.log"
  mv -f "$inspect_tmp" "$ARCHIVE_DIR/$archive_run/$name.inspect.json"
  sudo docker rm "$name" >/dev/null
  echo "Archived completed $name logs in artifacts/quattro-runs/$archive_run"
}

archive_stopped_container quickshell-quattro-smoke
archive_stopped_container hyprland-phase2-drm
RUN_STAMP="$(date +%Y%m%d-%H%M%S)-$$"

if [ "$CHECK_ONLY" -eq 1 ]; then
  exec env QUATTRO_RUN_ID="$RUN_STAMP" "$SCRIPT_DIR/run-hyprland-drm.sh" --stop-gdm --quattro --check
fi

echo "Starting Quattro lab session. Exit with Super+Shift+E; GDM will return."
exec env QUATTRO_RUN_ID="$RUN_STAMP" "$SCRIPT_DIR/run-hyprland-drm.sh" --stop-gdm --quattro
