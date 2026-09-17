#!/bin/sh
# Run this from the Jetson's active physical VT, not over SSH.
set -eu

case "$(id -u)" in
  0) ;;
  *) echo "Run with sudo from the active local VT." >&2; exit 1 ;;
esac

HOST_USER=looco
HOST_UID=$(id -u "$HOST_USER")
HOST_GID=$(id -g "$HOST_USER")
INPUT_GID=$(getent group input | cut -d: -f3)
VIDEO_GID=$(getent group video | cut -d: -f3)
RENDER_GID=$(getent group render | cut -d: -f3)

[ -n "$INPUT_GID" ] && [ -n "$VIDEO_GID" ] && [ -n "$RENDER_GID" ]
[ -d /run/udev/data ] || { echo "/run/udev/data is unavailable; host udev is required." >&2; exit 1; }
[ -c /dev/tty0 ] && [ -c /dev/tty1 ] && [ -d /dev/dri ] && [ -d /dev/input ]
if docker container inspect hyprland-phase2-drm >/dev/null 2>&1; then
  echo "Container hyprland-phase2-drm already exists. Inspect its logs or remove that exact stopped container first." >&2
  exit 1
fi

exec docker run -it \
  --name hyprland-phase2-drm \
  --network none \
  --runtime=nvidia \
  --gpus all \
  --device=/dev/dri \
  --device=/dev/input \
  --device-cgroup-rule='c 13:* rwm' \
  --mount type=bind,src=/run/udev,dst=/run/udev,readonly \
  --device=/dev/tty0 \
  --device=/dev/tty1 \
  --cap-add=SYS_TTY_CONFIG \
  -e HYPRLAND_UID="$HOST_UID" \
  -e HYPRLAND_GID="$HOST_GID" \
  -e HYPRLAND_INPUT_GID="$INPUT_GID" \
  -e HYPRLAND_VIDEO_GID="$VIDEO_GID" \
  -e HYPRLAND_RENDER_GID="$RENDER_GID" \
  -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
  hyprland:phase2-runtime
