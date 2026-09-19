#!/bin/sh
set -eu

: "${QS_BIN:=/tmp/quickshell-hypr-build/src/quickshell}"

# Keep the synced Omarchy checkout read-only. This disposable copy carries the
# one Qt/QML compatibility rename needed by the notification service: Qt's QML
# parser treats `transient` as a reserved identifier in this context.
OMARCHY_RUNTIME=/tmp/omarchy-runtime
install -d -m 0755 "$OMARCHY_RUNTIME"
cp -a /omarchy/. "$OMARCHY_RUNTIME/"
cp /test/jetson-power.qml "$OMARCHY_RUNTIME/shell/plugins/panels/power/Panel.qml"
cp /test/jetson-agents/Panel.qml "$OMARCHY_RUNTIME/shell/plugins/agents/Panel.qml"
install -d -m 0755 "$OMARCHY_RUNTIME/shell/plugins/panels/jetson-telemetry"
cp -a /test/jetson-telemetry/. "$OMARCHY_RUNTIME/shell/plugins/panels/jetson-telemetry/"
install -d -m 0755 "$OMARCHY_RUNTIME/shell/plugins/panels/jetson-workloads"
cp -a /test/jetson-workloads/. "$OMARCHY_RUNTIME/shell/plugins/panels/jetson-workloads/"
sed -i \
  -e 's/var transient = false/var transientHint = false/' \
  -e 's/transient = !!(notification\.hints/transientHint = !!(notification.hints/' \
  -e 's/{ transient = false }/{ transientHint = false }/' \
  -e 's/return transient || NotificationLogic/return transientHint || NotificationLogic/' \
  "$OMARCHY_RUNTIME/shell/plugins/notifications/Service.qml"
python3 - "$OMARCHY_RUNTIME/config/omarchy/shell.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    config = json.load(source)
right = config["bar"]["layout"]["right"]
entry = {"id": "omarchy.jetson-telemetry"}
if entry not in right:
    # Keep hardware status together: telemetry sits immediately before PWR.
    power_index = next((i for i, item in enumerate(right) if item.get("id") == "omarchy.power"), len(right))
    right.insert(power_index, entry)
workload_entry = {"id": "omarchy.jetson-workloads"}
if workload_entry not in right:
    agents_index = next((i for i, item in enumerate(right) if item.get("id") == "omarchy.agents"), len(right))
    right.insert(agents_index, workload_entry)
with open(path, "w", encoding="utf-8") as target:
    json.dump(config, target, indent=2)
    target.write("\n")
PY
export OMARCHY_PATH="$OMARCHY_RUNTIME"
export QML_IMPORT_PATH="$OMARCHY_RUNTIME/shell"
export PATH="/test/helpers:$PATH"

# The menu glyph is supplied by Omarchy's bundled font. Install it into this
# disposable container before Qt constructs its font database.
install -d -m 0755 /tmp/omarchy-fonts
cp "$OMARCHY_RUNTIME/default/fonts/omarchy/omarchy.ttf" /tmp/omarchy-fonts/omarchy.ttf
install -d -m 0755 /tmp/omarchy-fontconfig
cat > /tmp/omarchy-fontconfig/fonts.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/tmp/omarchy-fonts</dir>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <alias binding="strong">
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font</family></prefer>
  </alias>
</fontconfig>
EOF
export FONTCONFIG_FILE=/tmp/omarchy-fontconfig/fonts.conf
fc-cache -f >/dev/null
echo "Omarchy icon font: $(fc-match -f '%{family}\n' omarchy)"
echo "Bar icon font: $(fc-match -f '%{family}\n' monospace)"

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
      exec "$QS_BIN" --no-color --log-times -v -p "$OMARCHY_RUNTIME/shell/shell.qml"
    fi
  done
  sleep 1
  remaining=$((remaining - 1))
done

echo "No compositor socket appeared within 60 seconds." >&2
exit 1
