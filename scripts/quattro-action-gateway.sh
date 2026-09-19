#!/bin/sh
# Narrow, session-scoped action gateway for the Quattro lab.
# It deliberately accepts one fixed request and cannot execute caller-supplied
# commands or arguments.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REQUEST_DIR=${1:?Usage: quattro-action-gateway.sh REQUEST_DIRECTORY}
REQUEST_FILE="$REQUEST_DIR/submit-harmless-sample"
GATEWAY_LOG="$REQUEST_DIR/gateway.log"
ACTIVE_SAMPLE_ID=

[ -d "$REQUEST_DIR" ] || { echo "Action request directory does not exist: $REQUEST_DIR" >&2; exit 1; }

sample_running() {
  "$SCRIPT_DIR/quattro-workloads.sh" init
  jq -e '.jobs[]? | select(.name == "Harmless sample" and .state == "running")' \
    "$SCRIPT_DIR/../artifacts/workloads/registry.json" >/dev/null
}

active_sample_running() {
  [ -n "$ACTIVE_SAMPLE_ID" ] && jq -e --arg id "$ACTIVE_SAMPLE_ID" \
    '.jobs[]? | select(.id == $id and .state == "running")' \
    "$SCRIPT_DIR/../artifacts/workloads/registry.json" >/dev/null
}

cleanup() {
  # The fixed sample is session-scoped. If Quattro exits before it completes,
  # make the interrupted state explicit instead of leaving a stale "running"
  # record in the panel.
  if active_sample_running; then
    "$SCRIPT_DIR/quattro-workloads.sh" finish "$ACTIVE_SAMPLE_ID" 143 || true
    echo "Marked interrupted harmless sample as failed during gateway shutdown." >>"$GATEWAY_LOG"
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 143' HUP TERM
trap 'cleanup; exit 130' INT

echo "Quattro action gateway ready; only submit-harmless-sample-v1 is accepted." >>"$GATEWAY_LOG"
while :; do
  if [ -f "$REQUEST_FILE" ]; then
    request=$(cat "$REQUEST_FILE" 2>/dev/null || true)
    rm -f "$REQUEST_FILE"
    case "$request" in
      submit-harmless-sample-v1)
        if sample_running; then
          echo "Ignored duplicate harmless-sample request: a sample is already running." >>"$GATEWAY_LOG"
        else
          started=$("$SCRIPT_DIR/quattro-workloads.sh" sample 2>>"$GATEWAY_LOG" || true)
          case "$started" in
            'Started harmless sample workload: '*)
              ACTIVE_SAMPLE_ID=${started#Started harmless sample workload: }
              echo "$started" >>"$GATEWAY_LOG"
              ;;
            *) echo "Harmless-sample request failed." >>"$GATEWAY_LOG" ;;
          esac
        fi
        ;;
      *)
        echo "Rejected unknown action request." >>"$GATEWAY_LOG"
        ;;
    esac
  fi
  sleep 1
done
