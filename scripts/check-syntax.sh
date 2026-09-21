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
$SCRIPT_DIR/quattro-workloads.sh \
$SCRIPT_DIR/quattro-action-gateway.sh \
$SCRIPT_DIR/quattro-agent-adapter.sh \
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

python3 - "$ROOT_DIR/scripts/quattro-mvp.py" <<'PY'
import ast
import pathlib
import sys
ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])
PY

sh -n "$ROOT_DIR/tests/mvp/test-conductor.sh"
sh -n "$ROOT_DIR/tests/mvp/test-control-plane.sh"

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

command -v jq >/dev/null 2>&1 || {
  echo "Syntax check: jq is required for JSON validation" >&2
  exit 1
}
jq empty "$ROOT_DIR/tests/runtime-smoke/jetson-telemetry/manifest.json"
jq empty "$ROOT_DIR/tests/runtime-smoke/jetson-workloads/manifest.json"

echo "Syntax validation passed: shell launchers, helpers, and runtime manifest"
