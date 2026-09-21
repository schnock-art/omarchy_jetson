#!/bin/sh
# Narrow, session-scoped action gateway for the Quattro lab.
# It deliberately accepts one fixed request and cannot execute caller-supplied
# commands or arguments.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REQUEST_DIR=${1:?Usage: quattro-action-gateway.sh REQUEST_DIRECTORY}
AGENT_STATUS_FILE=${2:?Usage: quattro-action-gateway.sh REQUEST_DIRECTORY AGENT_STATUS_FILE RUN_ID}
RUN_ID=${3:?Usage: quattro-action-gateway.sh REQUEST_DIRECTORY AGENT_STATUS_FILE RUN_ID}
REQUEST_FILE="$REQUEST_DIR/action-request"
GATEWAY_LOG="$REQUEST_DIR/gateway.log"
ACTION_STATUS_FILE="$REQUEST_DIR/action-status.json"
MVP_STATUS_FILE="$REQUEST_DIR/mvp-status.json"
MVP_PID_FILE="$REQUEST_DIR/mvp-agent.pid"
ACTIVE_SAMPLE_ID=
LAST_REQUEST_ID=
MVP_AGENT_PID=
MVP_REQUEST_ID=
MVP_STATUS_FINGERPRINT=

[ -d "$REQUEST_DIR" ] || { echo "Action request directory does not exist: $REQUEST_DIR" >&2; exit 1; }

write_action_status() {
  state=$1
  message=$2
  action=${3:-unknown}
  request_id=${4:-unknown}
  tmp="$ACTION_STATUS_FILE.tmp"
  jq -cn --arg state "$state" --arg message "$message" --arg action "$action" \
    --arg requestId "$request_id" --arg updated "$(date --iso-8601=seconds)" \
    '{schemaVersion:1,state:$state,message:$message,action:$action,requestId:$requestId,updatedAt:$updated}' >"$tmp"
  mv "$tmp" "$ACTION_STATUS_FILE"
}

write_mvp_status() {
  state=$1
  raw_state=$2
  message=$3
  request_id=${4:-session}
  tmp="$MVP_STATUS_FILE.tmp"
  jq -cn --arg state "$state" --arg rawState "$raw_state" --arg message "$message" \
    --arg requestId "$request_id" --arg updated "$(date --iso-8601=seconds)" \
    '{schemaVersion:1,state:$state,rawState:$rawState,message:$message,requestId:$requestId,updatedAt:$updated}' >"$tmp"
  mv "$tmp" "$MVP_STATUS_FILE"
}

sync_mvp_status() {
  agent_status="$SCRIPT_DIR/../artifacts/quattro-runs/$RUN_ID/agent-run.json"
  [ -f "$agent_status" ] && jq -e . "$agent_status" >/dev/null 2>&1 || return 0
  raw_state=$(jq -r '.state // "failed"' "$agent_status")
  reason=$(jq -r '.reason // "MVP agent status changed."' "$agent_status")
  fingerprint="$raw_state:$reason"
  [ "$fingerprint" != "$MVP_STATUS_FINGERPRINT" ] || return 0
  case "$raw_state" in
    waiting-for-human) display_state=waiting ;;
    unavailable|completed|failed|running) display_state=$raw_state ;;
    *) display_state=unknown ;;
  esac
  write_mvp_status "$display_state" "$raw_state" "$reason" "${MVP_REQUEST_ID:-session}"
  MVP_STATUS_FINGERPRINT=$fingerprint
}

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

publish_mvp_status() {
  adapter_exit=$1
  MVP_AGENT_PID=
  unlink "$MVP_PID_FILE" 2>/dev/null || true
  agent_state=failed
  agent_reason="MVP agent exited with status $adapter_exit."
  agent_status="$SCRIPT_DIR/../artifacts/quattro-runs/$RUN_ID/agent-run.json"
  if [ -f "$agent_status" ] && jq -e . "$agent_status" >/dev/null 2>&1; then
    agent_state=$(jq -r '.state // "failed"' "$agent_status")
    agent_reason=$(jq -r '.reason // "MVP agent finished."' "$agent_status")
  fi
  case "$agent_state" in
    completed)
      write_action_status completed "$agent_reason" run-mvp-acceptance-v1 "$MVP_REQUEST_ID"
      ;;
    waiting-for-human)
      write_action_status waiting "$agent_reason" run-mvp-acceptance-v1 "$MVP_REQUEST_ID"
      ;;
    *)
      write_action_status failed "$agent_reason" run-mvp-acceptance-v1 "$MVP_REQUEST_ID"
      ;;
  esac
  sync_mvp_status
  echo "MVP agent terminal state: $agent_state ($agent_reason)" >>"$GATEWAY_LOG"
  MVP_REQUEST_ID=
}

update_mvp_status() {
  [ -n "$MVP_AGENT_PID" ] || return 0
  kill -0 "$MVP_AGENT_PID" 2>/dev/null && return 0
  if wait "$MVP_AGENT_PID"; then
    adapter_exit=0
  else
    adapter_exit=$?
  fi
  publish_mvp_status "$adapter_exit"
}

cleanup() {
  # The fixed sample is session-scoped. If Quattro exits before it completes,
  # make the interrupted state explicit instead of leaving a stale "running"
  # record in the panel.
  if active_sample_running; then
    "$SCRIPT_DIR/quattro-workloads.sh" finish "$ACTIVE_SAMPLE_ID" 143 || true
    echo "Marked interrupted harmless sample as failed during gateway shutdown." >>"$GATEWAY_LOG"
  fi
  if [ -n "$MVP_AGENT_PID" ] && kill -0 "$MVP_AGENT_PID" 2>/dev/null; then
    sync_mvp_status
    echo "Detached MVP adapter continues after gateway shutdown: $MVP_AGENT_PID" >>"$GATEWAY_LOG"
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 143' HUP TERM
trap 'cleanup; exit 130' INT

echo "Quattro action gateway ready; only fixed harmless-sample, Codex-refresh, and MVP-agent requests are accepted." >>"$GATEWAY_LOG"
write_action_status ready 'Ready for an explicit harmless sample or Codex usage refresh.' ready session
write_mvp_status not-started not-started 'No MVP agent has been approved for this run.' session
while :; do
  if [ -f "$REQUEST_FILE" ]; then
    if [ -L "$REQUEST_FILE" ]; then
      echo "Rejected symlink action request." >>"$GATEWAY_LOG"
      unlink "$REQUEST_FILE" 2>/dev/null || true
      write_action_status rejected 'Rejected a symlink action request.' rejected symlink
      continue
    fi
    request=$(cat "$REQUEST_FILE" 2>/dev/null || true)
    rm -f "$REQUEST_FILE"
    action=$request
    request_id="$(date +%Y%m%d-%H%M%S)-$$"
    if printf '%s' "$request" | jq -e . >/dev/null 2>&1; then
      action=$(printf '%s' "$request" | jq -r '.action // empty')
      request_id=$(printf '%s' "$request" | jq -r '.requestId // empty')
    fi
    [ -n "$request_id" ] || request_id="$(date +%Y%m%d-%H%M%S)-$$"
    if [ "$request_id" = "$LAST_REQUEST_ID" ]; then
      echo "Ignored duplicate action request: $request_id" >>"$GATEWAY_LOG"
      continue
    fi
    LAST_REQUEST_ID=$request_id
    case "$action" in
      submit-harmless-sample-v1)
        if sample_running; then
          echo "Ignored harmless-sample request: a sample is already running." >>"$GATEWAY_LOG"
          write_action_status rejected 'A harmless sample is already running.' "$action" "$request_id"
        else
          started=$("$SCRIPT_DIR/quattro-workloads.sh" sample 2>>"$GATEWAY_LOG" || true)
          case "$started" in
            'Started harmless sample workload: '*)
              ACTIVE_SAMPLE_ID=${started#Started harmless sample workload: }
              echo "$started" >>"$GATEWAY_LOG"
              write_action_status accepted 'Harmless 15-second sample started.' "$action" "$request_id"
              ;;
            *)
              echo "Harmless-sample request failed." >>"$GATEWAY_LOG"
              write_action_status failed 'Harmless sample could not be started.' "$action" "$request_id"
              ;;
          esac
        fi
        ;;
      refresh-codex-status-v1)
        write_action_status working 'Refreshing the existing Codex usage snapshot…' "$action" "$request_id"
        if timeout 50 "$SCRIPT_DIR/collect-jetson-agent-status.sh" --once "$AGENT_STATUS_FILE" >>"$GATEWAY_LOG" 2>&1; then
          write_action_status completed 'Codex usage snapshot refreshed.' "$action" "$request_id"
        else
          echo "Codex usage refresh failed." >>"$GATEWAY_LOG"
          write_action_status failed 'Codex usage refresh failed; the previous snapshot remains available.' "$action" "$request_id"
        fi
        ;;
      run-mvp-acceptance-v1)
        if [ -n "$MVP_AGENT_PID" ] && kill -0 "$MVP_AGENT_PID" 2>/dev/null; then
          write_action_status rejected 'An MVP agent is already running.' "$action" "$request_id"
        else
          write_action_status working 'Starting the explicitly approved host-side MVP agent.' "$action" "$request_id"
          setsid "$SCRIPT_DIR/quattro-agent-adapter.sh" --run-id "$RUN_ID" --approve --wait-for-session \
            >"$REQUEST_DIR/mvp-agent.log" 2>&1 </dev/null &
          MVP_AGENT_PID=$!
          MVP_REQUEST_ID=$request_id
          printf '%s\n' "$MVP_AGENT_PID" >"$MVP_PID_FILE"
          write_mvp_status waiting waiting-for-human 'Approved. Exit Quattro normally; Codex will start after archival.' "$request_id"
          write_action_status accepted 'MVP agent approved and waiting for normal Quattro exit.' "$action" "$request_id"
        fi
        ;;
      *)
        echo "Rejected unknown action request." >>"$GATEWAY_LOG"
        write_action_status rejected 'Rejected an unknown action request.' "$action" "$request_id"
        ;;
    esac
  fi
  update_mvp_status
  sync_mvp_status
  sleep 1
done
