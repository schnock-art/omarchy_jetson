#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/quattro-session-common.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
MOCK_DIR="$TEST_ROOT/mock"
ARCHIVE_DIR="$TEST_ROOT/archive"
mkdir -p "$MOCK_DIR" "$ARCHIVE_DIR"

. "$ROOT_DIR/scripts/quattro-session-common.sh"

fail() {
  echo "session common fixture failed: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file $1"
}

assert_absent() {
  [ ! -e "$1" ] || fail "unexpected path $1"
}

quattro_docker() {
  operation=$1
  shift
  case "$operation" in
    container)
      [ "$1" = inspect ] || return 90
      shift
      if [ "${1:-}" = -f ]; then
        format=$2
        name=$3
        [ -f "$MOCK_DIR/$name.state" ] || return 1
        case "$format" in
          '{{.State.Status}}') cat "$MOCK_DIR/$name.state" ;;
          *run-id*) cat "$MOCK_DIR/$name.label" 2>/dev/null || true ;;
          *) return 91 ;;
        esac
      else
        name=$1
        [ -f "$MOCK_DIR/$name.state" ]
      fi
      ;;
    logs)
      name=$1
      if [ -f "$MOCK_DIR/$name.logs-fail" ]; then
        echo 'partial log output'
        return 1
      fi
      echo "logs:$name"
      ;;
    inspect)
      name=$1
      [ ! -f "$MOCK_DIR/$name.inspect-fail" ] || return 1
      printf '{"name":"%s"}\n' "$name"
      ;;
    rm)
      name=$1
      rm -f "$MOCK_DIR/$name.state"
      : >"$MOCK_DIR/$name.removed"
      ;;
    *) return 92 ;;
  esac
}

# Backend and identifier policy fails closed before any lifecycle work.
quattro_validate_backend lab-vt
quattro_validate_backend gdm-session
if quattro_validate_backend arbitrary; then fail 'unknown backend was accepted'; fi
quattro_require_backend lab-vt lab-vt
if quattro_require_backend gdm-session lab-vt; then fail 'unimplemented backend was accepted'; fi
quattro_validate_run_id run_20260922-1
if quattro_validate_run_id '../escape'; then fail 'unsafe run ID was accepted'; fi
[ "$(quattro_container_label run-1)" = 'dev.omarchy-quattro.run-id=run-1' ] || fail 'wrong container label'

# Missing containers and repeated cleanup are idempotent.
quattro_archive_stopped_container missing "$ARCHIVE_DIR" fallback-run
quattro_archive_stopped_container missing "$ARCHIVE_DIR" fallback-run

# A stopped labelled container is archived atomically and then removed.
printf '%s\n' exited >"$MOCK_DIR/quickshell.state"
printf '%s\n' accepted-run >"$MOCK_DIR/quickshell.label"
quattro_archive_stopped_container quickshell "$ARCHIVE_DIR" fallback-run
assert_file "$ARCHIVE_DIR/accepted-run/quickshell.log"
assert_file "$ARCHIVE_DIR/accepted-run/quickshell.inspect.json"
assert_file "$MOCK_DIR/quickshell.removed"
assert_absent "$ARCHIVE_DIR/accepted-run/.quickshell.log.$$"

# An invalid label uses the caller's validated recovery run.
printf '%s\n' exited >"$MOCK_DIR/fallback.state"
printf '%s\n' '../bad' >"$MOCK_DIR/fallback.label"
quattro_archive_stopped_container fallback "$ARCHIVE_DIR" fallback-run
assert_file "$ARCHIVE_DIR/fallback-run/fallback.log"

# Duplicate/running ownership fails without removing or replacing evidence.
printf '%s\n' running >"$MOCK_DIR/running.state"
if quattro_archive_stopped_container running "$ARCHIVE_DIR" fallback-run; then
  fail 'running duplicate container was accepted'
fi
assert_file "$MOCK_DIR/running.state"
assert_absent "$MOCK_DIR/running.removed"

# A partial start is recoverable: archive the stopped half and ignore the absent half.
printf '%s\n' exited >"$MOCK_DIR/partial-shell.state"
printf '%s\n' partial-run >"$MOCK_DIR/partial-shell.label"
quattro_archive_stopped_container partial-shell "$ARCHIVE_DIR" fallback-run
quattro_archive_stopped_container partial-compositor "$ARCHIVE_DIR" fallback-run
assert_file "$ARCHIVE_DIR/partial-run/partial-shell.inspect.json"

# Inspection failure preserves the container and publishes no partial archive.
printf '%s\n' exited >"$MOCK_DIR/broken.state"
printf '%s\n' broken-run >"$MOCK_DIR/broken.label"
: >"$MOCK_DIR/broken.inspect-fail"
if quattro_archive_stopped_container broken "$ARCHIVE_DIR" fallback-run; then
  fail 'archive inspection failure was hidden'
fi
assert_file "$MOCK_DIR/broken.state"
assert_absent "$MOCK_DIR/broken.removed"
assert_absent "$ARCHIVE_DIR/broken-run/broken.log"
assert_absent "$ARCHIVE_DIR/broken-run/broken.inspect.json"

# Atomic file replacement never exposes the temporary name.
printf '%s\n' old >"$ARCHIVE_DIR/status.json"
printf '%s\n' new >"$TEST_ROOT/source.json"
quattro_archive_file "$TEST_ROOT/source.json" "$ARCHIVE_DIR" status.json
[ "$(cat "$ARCHIVE_DIR/status.json")" = new ] || fail 'archive replacement did not publish new content'
assert_absent "$ARCHIVE_DIR/.status.json.$$"

# Session states are validated and published atomically.
quattro_write_session_record "$ARCHIVE_DIR/session-run" session-run restoring-gdm revision-1
jq -e '.schemaVersion == 1 and .runId == "session-run" and .state == "restoring-gdm" and .revision == "revision-1"' \
  "$ARCHIVE_DIR/session-run/session.json" >/dev/null || fail 'invalid session record'
quattro_write_session_record "$ARCHIVE_DIR/session-run" session-run failed revision-1 7
jq -e '.state == "failed" and .exitCode == 7' "$ARCHIVE_DIR/session-run/session.json" >/dev/null || fail 'missing terminal exit code'
if quattro_write_session_record "$ARCHIVE_DIR/session-run" session-run invented revision-1; then
  fail 'unknown session state was accepted'
fi
assert_absent "$ARCHIVE_DIR/session-run/.session.json.$$"

# Startup waits are bounded and cleanup is safe after signal/duplicate calls.
if quattro_wait_for_path file "$TEST_ROOT/never" 0; then fail 'zero timeout unexpectedly succeeded'; fi
( sleep 0.1; printf '%s\n' ready >"$TEST_ROOT/ready" ) &
writer_pid=$!
quattro_wait_for_path file "$TEST_ROOT/ready" 2
wait "$writer_pid"
sleep 30 &
owned_pid=$!
# Let the child replace the forked shell before signalling it; otherwise a very
# fast kill can leave the eventual sleep holding the fixture's output pipe.
sleep 0.1
quattro_stop_pid "$owned_pid"
if kill -0 "$owned_pid" 2>/dev/null; then fail 'owned process survived cleanup'; fi
quattro_stop_pid "$owned_pid"
quattro_stop_pid ''

echo 'Session lifecycle common fixture checks passed'
