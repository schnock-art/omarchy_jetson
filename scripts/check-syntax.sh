#!/bin/sh
# Validate shell and JSON/QML-adjacent launcher inputs before a physical test.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

shell_files="\
$SCRIPT_DIR/check-syntax.sh \
$SCRIPT_DIR/start-quattro-lab.sh \
$SCRIPT_DIR/run-hyprland-drm.sh \
$SCRIPT_DIR/collect-jetson-telemetry.sh \
$SCRIPT_DIR/collect-jetson-agent-status.sh \
$SCRIPT_DIR/quattro-health-report.sh \
$SCRIPT_DIR/quattro-reboot-check.sh \
$ROOT_DIR/tests/runtime-smoke/run-quattro-shell.sh \
$ROOT_DIR/tests/runtime-smoke/run-layer-panel.sh \
$ROOT_DIR/tests/runtime-smoke/helpers/busctl \
$ROOT_DIR/tests/runtime-smoke/helpers/omarchy-bluetooth-power \
$ROOT_DIR/tests/runtime-smoke/helpers/omarchy-network-status"

for file in $shell_files; do
  [ -f "$file" ] || { echo "Syntax check: missing $file" >&2; exit 1; }
  case "$file" in
    */collect-jetson-agent-status.sh|*/quattro-health-report.sh)
      bash -n "$file" ;;
    */tests/runtime-smoke/helpers/busctl|*/tests/runtime-smoke/helpers/omarchy-bluetooth-power|*/tests/runtime-smoke/helpers/omarchy-network-status)
      python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' "$file" ;;
    *)
      sh -n "$file" ;;
  esac
done

for file in \
  "$ROOT_DIR/tests/runtime-smoke/jetson-telemetry/manifest.json" \
  "$ROOT_DIR/tests/runtime-smoke/jetson-agents/Panel.qml"; do
  [ -f "$file" ] || { echo "Syntax check: missing $file" >&2; exit 1; }
done

command -v jq >/dev/null 2>&1 || {
  echo "Syntax check: jq is required for JSON validation" >&2
  exit 1
}
jq empty "$ROOT_DIR/tests/runtime-smoke/jetson-telemetry/manifest.json"

echo "Syntax validation passed: shell launchers, helpers, and runtime manifest"
