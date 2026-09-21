#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/quattro-session-services.XXXXXX)
trap 'quattro_services_stop 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
FIXTURE_BIN="$ROOT_DIR/tests/session/helpers"
FIXTURE_SCRIPTS="$TEST_ROOT/scripts"
ARCHIVE_DIR="$TEST_ROOT/archive"
mkdir -p "$FIXTURE_SCRIPTS" "$ARCHIVE_DIR"
PATH="$FIXTURE_BIN:$PATH"
export PATH
QUATTRO_SERVICE_READY_TIMEOUT=2
export QUATTRO_SERVICE_READY_TIMEOUT

ln -s "$FIXTURE_BIN/fixture-system-bus.sh" "$FIXTURE_SCRIPTS/system-bus-readonly.sh"
ln -s "$FIXTURE_BIN/fixture-json-collector.sh" "$FIXTURE_SCRIPTS/collect-jetson-telemetry.sh"
ln -s "$FIXTURE_BIN/fixture-json-collector.sh" "$FIXTURE_SCRIPTS/collect-jetson-agent-status.sh"
ln -s "$FIXTURE_BIN/fixture-action-gateway.sh" "$FIXTURE_SCRIPTS/quattro-action-gateway.sh"

. "$ROOT_DIR/scripts/quattro-session-common.sh"
. "$ROOT_DIR/scripts/quattro-session-services.sh"

fail() {
  echo "session services fixture failed: $*" >&2
  exit 1
}

quattro_docker() {
  [ "$1" = run ] || fail "unexpected docker operation: $1"
  return 0
}

process_is_live() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

quattro_services_init
quattro_services_are_idle || fail 'fresh service owner was not idle'
quattro_services_start "$FIXTURE_SCRIPTS" fixture "$(id -u)" "$(id -g)" "$PATH" fixture-image /fixture/quickshell service-run

process_is_live "$SYSTEM_PROXY_PID" || fail 'system proxy did not remain live'
process_is_live "$TELEMETRY_PID" || fail 'telemetry collector did not remain live'
process_is_live "$AGENT_STATUS_PID" || fail 'agent collector did not remain live'
process_is_live "$ACTION_GATEWAY_PID" || fail 'action gateway did not remain live'
[ -S "$SYSTEM_PROXY_DIR/bus" ] || fail 'system proxy socket missing'
[ -s "$TELEMETRY_DIR/telemetry.json" ] || fail 'telemetry record missing'
[ -s "$AGENT_STATUS_DIR/status.json" ] || fail 'agent record missing'
[ "$(stat -c %a "$ACTION_GATEWAY_DIR")" = 700 ] || fail 'gateway directory permissions widened'
case "$QS_ACTION_ARGS" in *'/tmp/jetson-actions'*) ;; *) fail 'gateway mount missing' ;; esac

if quattro_services_start "$FIXTURE_SCRIPTS" fixture "$(id -u)" "$(id -g)" "$PATH" fixture-image /fixture/quickshell duplicate-run; then
  fail 'duplicate service ownership was accepted'
fi

quattro_services_archive "$ARCHIVE_DIR"
for evidence in agent-status.json telemetry.json action-status.json mvp-status.json action-gateway.log action-launcher.log; do
  [ -f "$ARCHIVE_DIR/$evidence" ] || fail "missing archived service evidence: $evidence"
done

# Simulate one interrupted child; aggregate cleanup must remain idempotent.
kill -TERM "$AGENT_STATUS_PID"
wait "$AGENT_STATUS_PID" 2>/dev/null || true
quattro_services_stop
quattro_services_are_idle || fail 'service owner was not idle after cleanup'
quattro_services_stop

# A readiness timeout after a partial start is reported and all owned children
# remain recoverable by the same aggregate cleanup path.
QUATTRO_FIXTURE_COLLECTOR_FAIL=1
export QUATTRO_FIXTURE_COLLECTOR_FAIL
if quattro_services_start "$FIXTURE_SCRIPTS" fixture "$(id -u)" "$(id -g)" "$PATH" fixture-image /fixture/quickshell timeout-run; then
  fail 'collector readiness timeout was hidden'
fi
process_is_live "$SYSTEM_PROXY_PID" || fail 'partial-start proxy ownership was lost'
process_is_live "$TELEMETRY_PID" || fail 'partial-start collector ownership was lost'
quattro_services_stop
quattro_services_are_idle || fail 'partial-start cleanup was incomplete'

if quattro_services_start "$FIXTURE_SCRIPTS" '../bad' "$(id -u)" "$(id -g)" "$PATH" fixture-image /fixture/quickshell invalid-user-run; then
  fail 'invalid service identity was accepted'
fi
quattro_services_are_idle || fail 'identity validation started a process'

echo 'Session service ownership fixture checks passed'
