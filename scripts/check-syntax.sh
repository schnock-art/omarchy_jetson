#!/bin/sh
# Validate shell and JSON/QML-adjacent launcher inputs before a physical test.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

shell_files="\
$SCRIPT_DIR/check-syntax.sh \
$SCRIPT_DIR/start-quattro-lab.sh \
$SCRIPT_DIR/run-hyprland-drm.sh \
$SCRIPT_DIR/quattro-session-common.sh \
$SCRIPT_DIR/quattro-session-services.sh \
$SCRIPT_DIR/quattro-gdm-session-runtime.sh \
$SCRIPT_DIR/collect-jetson-telemetry.sh \
$SCRIPT_DIR/collect-jetson-agent-status.sh \
$SCRIPT_DIR/quattro-health-report.sh \
$SCRIPT_DIR/quattro-reboot-check.sh \
$SCRIPT_DIR/quattro-workloads.sh \
$SCRIPT_DIR/quattro-action-gateway.sh \
$SCRIPT_DIR/quattro-agent-adapter.sh \
$ROOT_DIR/containers/hyprland-runtime/hyprland-seatd-entrypoint \
$ROOT_DIR/containers/hyprland-runtime/hyprland-unprivileged \
$ROOT_DIR/tests/session/helpers/setpriv \
$ROOT_DIR/tests/session/helpers/xdg-dbus-proxy \
$ROOT_DIR/tests/session/helpers/fixture-system-bus.sh \
$ROOT_DIR/tests/session/helpers/fixture-json-collector.sh \
$ROOT_DIR/tests/session/helpers/fixture-action-gateway.sh \
$ROOT_DIR/tests/runtime-smoke/run-quattro-shell.sh \
$ROOT_DIR/tests/runtime-smoke/run-layer-panel.sh \
$ROOT_DIR/tests/runtime-smoke/helpers/busctl \
$ROOT_DIR/tests/runtime-smoke/helpers/omarchy-bluetooth-power \
$ROOT_DIR/tests/runtime-smoke/helpers/omarchy-network-status"

for file in $shell_files; do
  [ -f "$file" ] || { echo "Syntax check: missing $file" >&2; exit 1; }
  case "$file" in
    */collect-jetson-agent-status.sh|*/quattro-health-report.sh|*/quattro-agent-adapter.sh)
      bash -n "$file" ;;
    */tests/runtime-smoke/helpers/busctl|*/tests/runtime-smoke/helpers/omarchy-bluetooth-power|*/tests/runtime-smoke/helpers/omarchy-network-status)
      python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' "$file" ;;
    *)
      sh -n "$file" ;;
  esac
done

python3 - "$ROOT_DIR/scripts/quattro-mvp.py" \
  "$ROOT_DIR/scripts/quattro-session-probe.py" \
  "$ROOT_DIR/scripts/quattro-gdm-wayland-experiment.py" \
  "$ROOT_DIR/scripts/quattro-gdm-session-service.py" \
  "$ROOT_DIR/scripts/quattro-gdm-session-wrapper.py" \
  "$ROOT_DIR/scripts/quattro-gdm-session-install.py" \
  "$ROOT_DIR/scripts/quattro-gdm-session-entry.py" \
  "$ROOT_DIR/tests/session/test-session-probe.py" \
  "$ROOT_DIR/tests/session/test-gdm-wayland-experiment.py" \
  "$ROOT_DIR/tests/session/test-gdm-session-control.py" \
  "$ROOT_DIR/tests/session/test-gdm-session-install.py" \
  "$ROOT_DIR/tests/session/test-gdm-session-wrapper.py" \
  "$ROOT_DIR/tests/session/test-gdm-session-entry.py" <<'PY'
import ast
import pathlib
import sys
for filename in sys.argv[1:]:
    ast.parse(pathlib.Path(filename).read_text(encoding="utf-8"), filename=filename)
PY

sh -n "$ROOT_DIR/tests/mvp/test-conductor.sh"
sh -n "$ROOT_DIR/tests/mvp/test-control-plane.sh"
sh -n "$ROOT_DIR/tests/session/test-session-common.sh"
sh -n "$ROOT_DIR/tests/session/test-session-vt.sh"
sh -n "$ROOT_DIR/tests/session/test-session-services.sh"
sh -n "$ROOT_DIR/tests/session/test-gdm-session-runtime.sh"

for file in \
  "$ROOT_DIR/tests/runtime-smoke/jetson-telemetry/manifest.json" \
  "$ROOT_DIR/tests/runtime-smoke/jetson-agents/Panel.qml" \
  "$ROOT_DIR/tests/runtime-smoke/jetson-workloads/manifest.json" \
  "$ROOT_DIR/tests/runtime-smoke/jetson-workloads/Panel.qml"; do
  [ -f "$file" ] || { echo "Syntax check: missing $file" >&2; exit 1; }
done

[ -f "$ROOT_DIR/mvp/acceptance.json" ] || {
  echo "Syntax check: missing MVP acceptance manifest" >&2
  exit 1
}
jq empty "$ROOT_DIR/mvp/acceptance.json"

[ -f "$ROOT_DIR/gdm/omarchy-quattro.desktop" ] || {
  echo "Syntax check: missing GDM session entry" >&2
  exit 1
}
grep -Fqx 'Name=Quattro (Jetson preview)' "$ROOT_DIR/gdm/omarchy-quattro.desktop"
grep -Fqx 'Exec=/usr/libexec/omarchy-quattro/session-wrapper run-session' "$ROOT_DIR/gdm/omarchy-quattro.desktop"
grep -Fqx 'ListenStream=/run/omarchy-quattro/control.sock' "$ROOT_DIR/systemd/omarchy-quattro-session.socket"
grep -Fqx 'ExecStart=/usr/libexec/omarchy-quattro/session-service serve --systemd-activation' "$ROOT_DIR/systemd/omarchy-quattro-session.service"

command -v jq >/dev/null 2>&1 || {
  echo "Syntax check: jq is required for JSON validation" >&2
  exit 1
}
jq empty "$ROOT_DIR/tests/runtime-smoke/jetson-telemetry/manifest.json"
jq empty "$ROOT_DIR/tests/runtime-smoke/jetson-workloads/manifest.json"

echo "Syntax validation passed: shell launchers, helpers, and runtime manifest"
