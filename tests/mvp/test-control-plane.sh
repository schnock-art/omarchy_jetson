#!/bin/sh
# Fixture checks for the host-side agent lifecycle without launching Codex.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
test_root=$(mktemp -d /tmp/quattro-control-test.XXXXXX)
detached_pid=
cleanup() {
  if [ -n "$detached_pid" ] && kill -0 "$detached_pid" 2>/dev/null; then kill -TERM "$detached_pid" 2>/dev/null || true; fi
  case "$test_root" in /tmp/quattro-control-test.*) rm -rf -- "$test_root" ;; esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_root/scripts" "$test_root/artifacts/quattro-runs/complete" \
  "$test_root/artifacts/quattro-runs/interrupted" \
  "$test_root/artifacts/quattro-runs/gateway-interrupted" \
  "$test_root/omarchy/bin" "$test_root/gateway"
cp "$ROOT_DIR/scripts/quattro-agent-adapter.sh" "$test_root/scripts/"
cp "$ROOT_DIR/scripts/quattro-action-gateway.sh" "$test_root/scripts/"

cat >"$test_root/scripts/quattro-mvp.py" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$test_root/scripts/collect-jetson-agent-status.sh" <<'EOF'
#!/bin/sh
printf '%s\n' '{"schemaVersion":1,"codex":{"id":"codex","ready":true}}' >"$2"
EOF
cat >"$test_root/omarchy/bin/omarchy-default-agent" <<'EOF'
#!/bin/sh
printf '%s\n' codex
EOF
cat >"$test_root/omarchy/bin/omarchy-agent" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$test_root/omarchy/bin/codex" <<'EOF'
#!/bin/sh
summary=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) summary=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "${FAKE_CODEX_MODE:-complete}" in
  complete)
    printf '%s\n' 'fixture agent summary' >"$summary"
    ;;
  wait)
    trap 'printf "%s\n" terminated >"$FAKE_CODEX_MARKER"; exit 143' HUP INT TERM
    while :; do sleep 1; done
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$test_root/scripts/quattro-mvp.py" \
  "$test_root/scripts/collect-jetson-agent-status.sh" "$test_root/omarchy/bin/"*

env OMARCHY_PATH="$test_root/omarchy" FAKE_CODEX_MODE=complete \
  bash "$test_root/scripts/quattro-agent-adapter.sh" --run-id complete --approve --timeout 20
jq -e '.state == "completed"' "$test_root/artifacts/quattro-runs/complete/agent-run.json" >/dev/null
test -s "$test_root/artifacts/quattro-runs/complete/agent-summary.md"

marker="$test_root/interrupted.marker"
env OMARCHY_PATH="$test_root/omarchy" FAKE_CODEX_MODE=wait FAKE_CODEX_MARKER="$marker" \
  bash "$test_root/scripts/quattro-agent-adapter.sh" --run-id interrupted --approve --timeout 20 &
adapter_pid=$!
attempt=0
while [ "$attempt" -lt 50 ]; do
  jq -e '.state == "running"' "$test_root/artifacts/quattro-runs/interrupted/agent-run.json" >/dev/null 2>&1 && break
  sleep 0.1
  attempt=$((attempt + 1))
done
kill -TERM "$adapter_pid"
if wait "$adapter_pid"; then
  echo 'Interrupted adapter unexpectedly exited successfully.' >&2
  exit 1
fi
jq -e '.state == "failed" and (.reason | contains("interrupted"))' \
  "$test_root/artifacts/quattro-runs/interrupted/agent-run.json" >/dev/null
test -s "$marker"
test ! -d "$test_root/artifacts/quattro-runs/interrupted/agent.lock"

gateway_marker="$test_root/gateway-interrupted.marker"
printf '%s\n' '{}' >"$test_root/agent-status.json"
printf '%s\n' '{"schemaVersion":1,"state":"preflight"}' \
  >"$test_root/artifacts/quattro-runs/gateway-interrupted/session.json"
env OMARCHY_PATH="$test_root/omarchy" FAKE_CODEX_MODE=wait FAKE_CODEX_MARKER="$gateway_marker" \
  sh "$test_root/scripts/quattro-action-gateway.sh" "$test_root/gateway" \
    "$test_root/agent-status.json" gateway-interrupted &
gateway_pid=$!
printf '%s\n' '{"schemaVersion":1,"requestId":"fixture-request","action":"run-mvp-acceptance-v1"}' \
  >"$test_root/gateway/action-request"
attempt=0
while [ "$attempt" -lt 50 ]; do
  jq -e '.state == "waiting" and .rawState == "waiting-for-human"' \
    "$test_root/gateway/mvp-status.json" >/dev/null 2>&1 && break
  sleep 0.1
  attempt=$((attempt + 1))
done
detached_pid=$(cat "$test_root/gateway/mvp-agent.pid")

printf '%s\n' '{"schemaVersion":1,"requestId":"refresh-request","action":"refresh-codex-status-v1"}' \
  >"$test_root/gateway/action-request"
attempt=0
while [ "$attempt" -lt 50 ]; do
  jq -e '.state == "completed" and .action == "refresh-codex-status-v1"' \
    "$test_root/gateway/action-status.json" >/dev/null 2>&1 && break
  sleep 0.1
  attempt=$((attempt + 1))
done
jq -e '.state == "waiting" and .rawState == "waiting-for-human"' \
  "$test_root/gateway/mvp-status.json" >/dev/null

kill -TERM "$gateway_pid"
if wait "$gateway_pid"; then
  echo 'Interrupted gateway unexpectedly exited successfully.' >&2
  exit 1
fi
kill -0 "$detached_pid"
printf '%s\n' '{"schemaVersion":1,"state":"awaiting-visual-check"}' \
  >"$test_root/artifacts/quattro-runs/gateway-interrupted/session.json"
attempt=0
while [ "$attempt" -lt 50 ]; do
  jq -e '.state == "running"' \
    "$test_root/artifacts/quattro-runs/gateway-interrupted/agent-run.json" >/dev/null 2>&1 && break
  sleep 0.1
  attempt=$((attempt + 1))
done
bash "$test_root/scripts/quattro-agent-adapter.sh" --run-id gateway-interrupted --stop
attempt=0
while [ "$attempt" -lt 50 ]; do
  jq -e '.state == "failed" and (.reason | contains("interrupted"))' \
    "$test_root/artifacts/quattro-runs/gateway-interrupted/agent-run.json" >/dev/null 2>&1 && break
  sleep 0.1
  attempt=$((attempt + 1))
done
jq -e '.state == "failed" and (.reason | contains("interrupted"))' \
  "$test_root/artifacts/quattro-runs/gateway-interrupted/agent-run.json" >/dev/null
test -s "$gateway_marker"
detached_pid=

rg -F 'sudo -- env QUATTRO_RUN_ID="$RUN_ID"' "$ROOT_DIR/scripts/run-hyprland-drm.sh" >/dev/null
test "$(rg -c 'dev.omarchy-quattro.run-id=\$RUN_ID' "$ROOT_DIR/scripts/run-hyprland-drm.sh")" -eq 2
rg -F 'container_run=$(sudo docker container inspect' "$ROOT_DIR/scripts/start-quattro-lab.sh" >/dev/null
rg -F 'mv -f "$log_tmp" "$ARCHIVE_DIR/$archive_run/$name.log"' "$ROOT_DIR/scripts/start-quattro-lab.sh" >/dev/null
rg -F 'chown -R "$HOST_UID:$HOST_GID" "$SESSION_ARCHIVE_DIR"' "$ROOT_DIR/scripts/run-hyprland-drm.sh" >/dev/null
rg -F 'sandbox_workspace_write.network_access=true' "$ROOT_DIR/scripts/quattro-agent-adapter.sh" >/dev/null

echo 'MVP control-plane fixture checks passed'
