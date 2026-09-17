#!/bin/sh
set -eu
# The compositor creates its socket after the sibling container starts.
remaining=60
while [ "$remaining" -gt 0 ]; do
    for candidate in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$candidate" ]; then
            export WAYLAND_DISPLAY=${candidate##*/}
            echo "Connecting Quickshell to $WAYLAND_DISPLAY as uid $(id -u)"
            exec /tmp/quickshell-build/src/quickshell --no-color --log-times -p /test/layer-panel.qml
        fi
    done
    sleep 1
    remaining=$((remaining - 1))
done
echo "No compositor socket appeared within 60 seconds." >&2
exit 1
