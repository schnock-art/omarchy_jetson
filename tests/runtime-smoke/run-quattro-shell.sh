#!/bin/sh
set -eu

: "${QS_BIN:=/tmp/quickshell-hypr-build/src/quickshell}"

remaining=60
while [ "$remaining" -gt 0 ]; do
  for candidate in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$candidate" ]; then
      export WAYLAND_DISPLAY=${candidate##*/}
      for instance in "$XDG_RUNTIME_DIR"/hypr/*; do
        if [ -d "$instance" ]; then
          export HYPRLAND_INSTANCE_SIGNATURE=${instance##*/}
          break
        fi
      done
      echo "Launching full Quattro shell on $WAYLAND_DISPLAY as uid $(id -u)"
      exec "$QS_BIN" --no-color --log-times -v -p /omarchy/shell/shell.qml
    fi
  done
  sleep 1
  remaining=$((remaining - 1))
done

echo "No compositor socket appeared within 60 seconds." >&2
exit 1
