#!/bin/sh
# Verify archived reports do not consult live host or container state.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
test_root=$(mktemp -d /tmp/quattro-health-test.XXXXXX)
cleanup() {
  case "$test_root" in /tmp/quattro-health-test.*) rm -rf -- "$test_root" ;; esac
}
trap cleanup EXIT HUP INT TERM

run_dir="$test_root/artifacts/quattro-runs/fixture-run"
mkdir -p "$test_root/scripts" "$test_root/bin" "$run_dir"
cp "$ROOT_DIR/scripts/quattro-health-report.sh" "$test_root/scripts/"

for command in docker sudo git; do
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" called >>"$HOST_PROBE_MARKER"' 'exit 99' \
    >"$test_root/bin/$command"
  chmod +x "$test_root/bin/$command"
done

printf '%s\n' '{"schemaVersion":1,"revision":"fixture-revision"}' >"$run_dir/session.json"
printf '%s\n' \
  'Configuration Loaded' \
  'Hyprland event socket connected' \
  'Connection established' \
  'Registered notification server with dbus.' \
  'JETSON_POWER_PANEL_LOADED' \
  'Wayland connection broke' >"$run_dir/quickshell-quattro-smoke.log"
printf '%s\n' '{"codex":{"id":"codex","todayPrompts":0,"updatedAt":"fixture"}}' \
  >"$run_dir/agent-status.json"
printf '%s\n' '[{"State":{"ExitCode":0}}]' >"$run_dir/hyprland-phase2-drm.inspect.json"

marker="$test_root/host-probe-called"
HOST_PROBE_MARKER="$marker" PATH="$test_root/bin:$PATH" \
  bash "$test_root/scripts/quattro-health-report.sh" --run fixture-run \
  >"$test_root/report.txt"

test ! -e "$marker"
grep -Fq 'Revision:   fixture-revision' "$test_root/report.txt"
grep -Fq 'PASS  Hyprland exited cleanly' "$test_root/report.txt"
grep -Fq 'Summary: 10 pass, 0 warn, 0 fail' "$test_root/report.txt"
if grep -Fq 'Docker daemon' "$test_root/report.txt"; then
  echo 'Archived report consulted live Docker state.' >&2
  exit 1
fi

echo 'MVP archived health-report fixture checks passed'
