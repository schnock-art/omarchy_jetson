#!/bin/sh
set -eu

remaining=60
while [ "$remaining" -gt 0 ]; do
  for candidate in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$candidate" ]; then
      export WAYLAND_DISPLAY=${candidate##*/}
      echo "Launching full Quattro shell on $WAYLAND_DISPLAY as uid $(id -u)"
      exec /tmp/quickshell-build/src/quickshell --no-color --log-times -v -p /omarchy/shell/shell.qml
    fi
  done
  sleep 1
  remaining=$((remaining - 1))
done

echo "No compositor socket appeared within 60 seconds." >&2
exit 1
