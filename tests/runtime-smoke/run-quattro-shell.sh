#!/bin/sh
set -eu

: "${QS_BIN:=/tmp/quickshell-hypr-build/src/quickshell}"

# Keep the synced Omarchy checkout read-only. This disposable copy carries the
# one Qt/QML compatibility rename needed by the notification service: Qt's QML
# parser treats `transient` as a reserved identifier in this context.
OMARCHY_RUNTIME=/tmp/omarchy-runtime
install -d -m 0755 "$OMARCHY_RUNTIME"
cp -a /omarchy/. "$OMARCHY_RUNTIME/"
sed -i \
  -e 's/var transient = false/var transientHint = false/' \
  -e 's/transient = !!(notification\.hints/transientHint = !!(notification.hints/' \
  -e 's/{ transient = false }/{ transientHint = false }/' \
  -e 's/return transient || NotificationLogic/return transientHint || NotificationLogic/' \
  "$OMARCHY_RUNTIME/shell/plugins/notifications/Service.qml"
export OMARCHY_PATH="$OMARCHY_RUNTIME"
export QML_IMPORT_PATH="$OMARCHY_RUNTIME/shell"

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
</fontconfig>
EOF
export FONTCONFIG_FILE=/tmp/omarchy-fontconfig/fonts.conf
fc-cache -f >/dev/null
echo "Omarchy icon font: $(fc-match -f '%{family}\n' omarchy)"

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
