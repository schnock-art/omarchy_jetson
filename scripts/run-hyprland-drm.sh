#!/bin/sh
# Run this from the Jetson's active physical VT, not over SSH.
set -eu

STOP_GDM=0
CHECK_ONLY=0
PANEL=0
QUATTRO=0
ACTIVE_TTY=
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_CONFIG="$SCRIPT_DIR/../tests/runtime-smoke/hyprland.conf"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --stop-gdm) STOP_GDM=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --panel) PANEL=1; shift ;;
    --quattro) QUATTRO=1; shift ;;
    --tty) [ "$#" -ge 2 ] || exit 2; ACTIVE_TTY=$2; shift 2 ;;
    *) echo "Usage: $0 [--stop-gdm] [--panel|--quattro] [--check] [--tty /dev/ttyN]" >&2; exit 2 ;;
  esac
done
[ "$PANEL" -eq 0 ] || [ "$QUATTRO" -eq 0 ] || { echo "Choose --panel or --quattro, not both." >&2; exit 2; }

# Capture the original console BEFORE sudo creates its own pseudo-terminal.
ACTIVE_TTY=${ACTIVE_TTY:-${SUDO_TTY:-$(tty 2>/dev/null || true)}}
VT_NUMBER=${ACTIVE_TTY#/dev/tty}
case "$VT_NUMBER" in
  ''|0|*[!0-9]*)
    echo "Cannot resolve a physical VT (detected: $ACTIVE_TTY)." >&2
    echo "On the local text console run this script without sudo, or pass --tty /dev/tty3 if that is your console." >&2
    exit 1 ;;
esac
[ "$ACTIVE_TTY" = "/dev/tty$VT_NUMBER" ] || exit 1
[ "$VT_NUMBER" -le 63 ] || exit 1

case "$(id -u)" in
  0) ;;
  *)
    set -- --tty "$ACTIVE_TTY"
    [ "$STOP_GDM" -eq 0 ] || set -- "$@" --stop-gdm
    [ "$CHECK_ONLY" -eq 0 ] || set -- "$@" --check
    [ "$PANEL" -eq 0 ] || set -- "$@" --panel
    [ "$QUATTRO" -eq 0 ] || set -- "$@" --quattro
    exec sudo -- "$(readlink -f "$0")" "$@" ;;
esac

HOST_USER=looco
HOST_UID=$(id -u "$HOST_USER")
HOST_GID=$(id -g "$HOST_USER")
INPUT_GID=$(getent group input | cut -d: -f3)
VIDEO_GID=$(getent group video | cut -d: -f3)
RENDER_GID=$(getent group render | cut -d: -f3)

[ -n "$INPUT_GID" ] && [ -n "$VIDEO_GID" ] && [ -n "$RENDER_GID" ]
[ -d /run/udev/data ] || { echo "/run/udev/data is unavailable; host udev is required." >&2; exit 1; }
[ -c /dev/tty0 ] && [ -c "$ACTIVE_TTY" ] && [ -d /dev/dri ] && [ -d /dev/input ]
docker info >/dev/null
docker image inspect hyprland:phase2-runtime >/dev/null
[ -r "$TEST_CONFIG" ] || { echo "Missing test config: $TEST_CONFIG" >&2; exit 1; }
command -v chvt >/dev/null
command -v fgconsole >/dev/null
if [ "$PANEL" -eq 1 ] || [ "$QUATTRO" -eq 1 ]; then
  docker image inspect quickshell:phase1 >/dev/null
  QS_CONTAINER=quickshell-layer-smoke
  QS_RUNNER=/test/run-layer-panel.sh
  QS_IMAGE=quickshell:phase1
  QS_BIN=/tmp/quickshell-build/src/quickshell
  if [ "$QUATTRO" -eq 1 ]; then
    QS_CONTAINER=quickshell-quattro-smoke
    QS_RUNNER=/test/run-quattro-shell.sh
    QS_IMAGE=quickshell:phase1-hypr-services
    QS_BIN=/tmp/quickshell-services-build/src/quickshell
    [ -d /home/looco/omarchy/shell ]
    DBUS_RUNTIME_DIR=/run/user/$HOST_UID
    DBUS_SOCKET=$DBUS_RUNTIME_DIR/bus
    [ -d "$DBUS_RUNTIME_DIR" ] && [ -S "$DBUS_SOCKET" ] || {
      echo "The host user D-Bus runtime is unavailable: $DBUS_RUNTIME_DIR" >&2
      echo "Log in as $HOST_USER once before starting the Quattro test." >&2
      exit 1
    }
  else
    [ -r "$SCRIPT_DIR/../tests/runtime-smoke/layer-panel.qml" ]
  fi
  [ -r "$SCRIPT_DIR/../tests/runtime-smoke/${QS_RUNNER##*/}" ]
  if docker container inspect "$QS_CONTAINER" >/dev/null 2>&1; then
    echo "Container $QS_CONTAINER already exists; preserve or remove it before another shell test." >&2
    exit 1
  fi
fi
if docker container inspect hyprland-phase2-drm >/dev/null 2>&1; then
  echo "Container hyprland-phase2-drm already exists. Inspect its logs or remove that exact stopped container first." >&2
  exit 1
fi
echo "Preflight passed: console=$ACTIVE_TTY, image=hyprland:phase2-runtime, uid=$HOST_UID"
[ "$CHECK_ONLY" -eq 0 ] || exit 0
[ -t 0 ] || { echo "An interactive local console is required." >&2; exit 1; }
if [ "$(fgconsole)" != "$VT_NUMBER" ]; then
  echo "$ACTIVE_TTY is not the foreground console. Switch to it before starting." >&2
  exit 1
fi
if [ "$STOP_GDM" -eq 0 ] && systemctl is-active --quiet gdm3; then
  echo "GDM is active; use --stop-gdm for the coordinated handoff." >&2
  exit 1
fi

RESTORE_GDM=0
PANEL_STARTED=0
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$PANEL_STARTED" -eq 1 ]; then
    docker stop --time 3 "$QS_CONTAINER" >/dev/null 2>&1 || true
    echo "Quickshell logs retained: sudo docker logs $QS_CONTAINER"
  fi
  docker stop --time 5 hyprland-phase2-drm >/dev/null 2>&1 || true
  if [ "$RESTORE_GDM" -eq 1 ]; then
    systemctl start gdm3 || true
  fi
  echo "Test ended (status $result). Container logs retained: sudo docker logs hyprland-phase2-drm"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Stopping GDM can blank the active screen or switch VTs. Doing it here means
# this already-running process continues directly into the DRM compositor.
if [ "$STOP_GDM" -eq 1 ]; then
  # GDM's service can finish stopping while its separate logind session scope
  # is still tearing down Xorg, which can subsequently switch away from our VT.
  GRAPHICAL_SCOPES=
  for session in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    seat=$(loginctl show-session "$session" -p Seat --value 2>/dev/null || true)
    type=$(loginctl show-session "$session" -p Type --value 2>/dev/null || true)
    state=$(loginctl show-session "$session" -p State --value 2>/dev/null || true)
    if [ "$seat" = seat0 ] && [ "$state" != closing ]; then
      case "$type" in
        x11|wayland)
          scope=$(loginctl show-session "$session" -p Scope --value)
          GRAPHICAL_SCOPES="$GRAPHICAL_SCOPES $scope" ;;
      esac
    fi
  done
  if systemctl is-active --quiet gdm3; then RESTORE_GDM=1; fi
  systemctl stop gdm3
  echo "Waiting for the previous graphical session to finish shutting down..."
  remaining=60
  while :; do
    pending=
    for scope in $GRAPHICAL_SCOPES; do
      state=$(systemctl show "$scope" -p ActiveState --value)
      case "$state" in
        active|activating|deactivating) pending="$pending $scope" ;;
      esac
    done
    [ -n "$pending" ] || break
    if [ "$remaining" -eq 0 ]; then
      echo "Graphical sessions still shutting down:$pending. Aborting and restoring GDM." >&2
      exit 1
    fi
    sleep 1
    remaining=$((remaining - 1))
  done
fi
# GDM shutdown can change the foreground VT. seatd uses the active VT, so
# explicitly reactivate the SAME console whose device is passed to Docker.
chvt "$VT_NUMBER"
[ "$(fgconsole)" = "$VT_NUMBER" ] || { echo "Failed to activate $ACTIVE_TTY" >&2; exit 1; }

set --
if [ "$PANEL" -eq 1 ] || [ "$QUATTRO" -eq 1 ]; then
  # An isolated volume shares only this test's runtime directory, not the host's.
  RUNTIME_VOLUME="jetson-wayland-$(date +%Y%m%d-%H%M%S)-$$"
  docker volume create "$RUNTIME_VOLUME" >/dev/null
  echo "Shared runtime volume retained for diagnostics: $RUNTIME_VOLUME"
  PANEL_STARTED=1
  QS_ARGS="--mount type=bind,src=$SCRIPT_DIR/../tests/runtime-smoke,dst=/test,readonly"
  if [ "$QUATTRO" -eq 1 ]; then
    QS_ARGS="$QS_ARGS --mount type=bind,src=/home/looco/omarchy,dst=/omarchy,readonly"
    QS_ARGS="$QS_ARGS --mount type=bind,src=$DBUS_RUNTIME_DIR,dst=$DBUS_RUNTIME_DIR"
    QS_ARGS="$QS_ARGS -e OMARCHY_PATH=/omarchy -e QML_IMPORT_PATH=/omarchy/shell"
    QS_ARGS="$QS_ARGS -e DBUS_SESSION_BUS_ADDRESS=unix:path=$DBUS_SOCKET"
  fi
  # shellcheck disable=SC2086
  docker run -d --name "$QS_CONTAINER" \
    --network none --runtime=nvidia --gpus all --device=/dev/dri \
    --user "$HOST_UID:$HOST_GID" \
    --group-add "$VIDEO_GID" --group-add "$RENDER_GID" \
    --mount "type=volume,src=$RUNTIME_VOLUME,dst=/tmp/hypr-runtime" \
    $QS_ARGS \
    -e HOME=/tmp -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
    -e QS_BIN="$QS_BIN" \
    --mount type=bind,src=/etc/localtime,dst=/etc/localtime,readonly \
    -e LANG=C.UTF-8 \
    -e QT_QPA_PLATFORM=wayland \
    --entrypoint sh "$QS_IMAGE" "$QS_RUNNER"
  set -- --mount "type=volume,src=$RUNTIME_VOLUME,dst=/tmp/hypr-runtime"
fi

docker run -it \
  "$@" \
  --name hyprland-phase2-drm \
  --network none \
  --runtime=nvidia \
  --gpus all \
  --device=/dev/dri \
  --device=/dev/input \
  --device-cgroup-rule='c 13:* rwm' \
  --mount type=bind,src=/run/udev,dst=/run/udev,readonly \
  --mount "type=bind,src=$TEST_CONFIG,dst=/etc/hyprland-smoke.conf,readonly" \
  --device=/dev/tty0 \
  --device="$ACTIVE_TTY" \
  --cap-add=SYS_TTY_CONFIG \
  -e HYPRLAND_UID="$HOST_UID" \
  -e HYPRLAND_GID="$HOST_GID" \
  -e HYPRLAND_INPUT_GID="$INPUT_GID" \
  -e HYPRLAND_VIDEO_GID="$VIDEO_GID" \
  -e HYPRLAND_RENDER_GID="$RENDER_GID" \
  -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
  hyprland:phase2-runtime --config /etc/hyprland-smoke.conf
