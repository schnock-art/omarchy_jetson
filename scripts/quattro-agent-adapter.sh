#!/bin/bash
# Explicit host-side adapter for the configured Omarchy coding agent.
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OMARCHY_BIN=${OMARCHY_PATH:-/home/looco/omarchy}/bin
AGENT_PATH="$OMARCHY_BIN:/usr/lib/chatgpt/resources:$PATH"
RUN_ID=
APPROVE=0
STOP=0
WAIT_FOR_SESSION=0
MAX_SECONDS=1800
SESSION_WAIT_SECONDS=7200
AGENT_PID=

usage() {
  echo "Usage: $0 --run-id RUN_ID (--approve [--wait-for-session] [--timeout SECONDS] | --stop)" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-id) [ "$#" -ge 2 ] || usage; RUN_ID=$2; shift 2 ;;
    --approve) APPROVE=1; shift ;;
    --stop) STOP=1; shift ;;
    --wait-for-session) WAIT_FOR_SESSION=1; shift ;;
    --timeout) [ "$#" -ge 2 ] || usage; MAX_SECONDS=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$RUN_ID" ] || usage
[ "$APPROVE" -eq 1 ] || [ "$STOP" -eq 1 ] || usage
[ "$APPROVE" -eq 0 ] || [ "$STOP" -eq 0 ] || usage
[ "$(id -u)" -ne 0 ] || { echo "Run the agent adapter as the desktop user, not root." >&2; exit 1; }
case "$RUN_ID" in *[!A-Za-z0-9_-]*|'') echo "Invalid run ID." >&2; exit 2 ;; esac
case "$MAX_SECONDS" in ''|*[!0-9]*) echo "Timeout must be an integer." >&2; exit 2 ;; esac

RUN_DIR="$ROOT_DIR/artifacts/quattro-runs/$RUN_ID"
LOCK_DIR="$RUN_DIR/agent.lock"
STATUS_FILE="$RUN_DIR/agent-run.json"
LOG_FILE="$RUN_DIR/agent.log"
SUMMARY_FILE="$RUN_DIR/agent-summary.md"
[ -d "$RUN_DIR" ] || { echo "Run archive does not exist: $RUN_ID" >&2; exit 1; }
if [ "$STOP" -eq 1 ]; then
  adapter_pid=$(jq -r '.pid // empty' "$STATUS_FILE" 2>/dev/null || true)
  case "$adapter_pid" in
    ''|*[!0-9]*) echo "No active adapter PID is recorded for run $RUN_ID." >&2; exit 1 ;;
  esac
  if kill -0 "$adapter_pid" 2>/dev/null; then
    kill -TERM "$adapter_pid"
    echo "Requested stop for MVP adapter $adapter_pid in run $RUN_ID."
    exit 0
  fi
  echo "Recorded MVP adapter $adapter_pid is no longer running." >&2
  exit 1
fi
mkdir "$LOCK_DIR" 2>/dev/null || { echo "Another agent already owns run $RUN_ID." >&2; exit 1; }
cleanup() { rmdir "$LOCK_DIR" 2>/dev/null || true; }

write_status() {
  state=$1
  reason=$2
  tmp="$STATUS_FILE.tmp"
  jq -cn --arg runId "$RUN_ID" --arg state "$state" --arg reason "$reason" \
    --arg updatedAt "$(date --iso-8601=seconds)" --argjson pid "$$" \
    '{schemaVersion:1,runId:$runId,state:$state,reason:$reason,pid:$pid,updatedAt:$updatedAt}' >"$tmp"
  mv "$tmp" "$STATUS_FILE"
}

interrupt_agent() {
  signal=$1
  code=$2
  trap - HUP INT TERM
  if [ -n "$AGENT_PID" ] && kill -0 "$AGENT_PID" 2>/dev/null; then
    kill -TERM -- "-$AGENT_PID" 2>/dev/null || kill -TERM "$AGENT_PID" 2>/dev/null || true
    wait "$AGENT_PID" 2>/dev/null || true
  fi
  AGENT_PID=
  write_status failed "Agent adapter interrupted by $signal"
  exit "$code"
}
trap cleanup EXIT
trap 'interrupt_agent HUP 129' HUP
trap 'interrupt_agent INT 130' INT
trap 'interrupt_agent TERM 143' TERM

"$SCRIPT_DIR/quattro-mvp.py" preflight >/dev/null
[ -x "$OMARCHY_BIN/omarchy-agent" ] || { write_status unavailable "Omarchy agent helper is missing: $OMARCHY_BIN/omarchy-agent"; exit 1; }
[ -x "$OMARCHY_BIN/omarchy-default-agent" ] || { write_status unavailable "Omarchy default-agent helper is missing: $OMARCHY_BIN/omarchy-default-agent"; exit 1; }
agent=$(PATH="$AGENT_PATH" "$OMARCHY_BIN/omarchy-default-agent" 2>/dev/null || true)
[ -n "$agent" ] || { write_status unavailable 'No Omarchy default agent is configured'; exit 1; }

if [ "$WAIT_FOR_SESSION" -eq 1 ]; then
  write_status waiting-for-human 'Exit Quattro normally; the approved agent will start after the run archive is complete.'
  waited=0
  while :; do
    session_state=$(jq -r '.state // empty' "$RUN_DIR/session.json" 2>/dev/null || true)
    case "$session_state" in
      awaiting-visual-check|failed|complete) break ;;
    esac
    if [ "$waited" -ge "$SESSION_WAIT_SECONDS" ]; then
      write_status failed "Run archive did not become complete within $SESSION_WAIT_SECONDS seconds"
      exit 124
    fi
    sleep 2
    waited=$((waited + 2))
  done
fi

write_status running "Running the approved MVP task with $agent"
prompt="Work on the completed Quattro Jetson MVP run $RUN_ID in $ROOT_DIR. The physical session has ended and its evidence is archived. Follow AGENTS.md and docs/MVP_IMPLEMENTATION_PLAN.md. Inspect only the selected run bundle for acceptance evidence. Run safe, repository-scoped checks and fixes. Do not stop GDM, hand off a VT, modify /home/looco/omarchy, install packages, or change JetPack/NVIDIA/firmware. Use scripts/quattro-mvp.py for deterministic evaluation; use --write-result only when deliberately finalizing an evaluation. If the visual assertion is still required, atomically record state waiting-for-human and waitingFor visual-check in $ROOT_DIR/artifacts/quattro-runs/$RUN_ID/agent-run.json, then explain the exact recording command in the summary. Finish with a concise summary in $ROOT_DIR/artifacts/quattro-runs/$RUN_ID/agent-summary.md."

case "$agent" in
  codex)
    # omarchy-agent intentionally launches the interactive Codex TUI. The MVP
    # adapter has no terminal, so use Codex's supported non-interactive entry
    # point while retaining Omarchy's configured-agent selection.
    # Sharing the host network avoids Ubuntu 24.04's blocked loopback namespace
    # setup while preserving Codex's workspace-write filesystem boundary.
    # See docs/AGENT_INTEGRATION.md for the observed AppArmor constraint.
    agent_command=(codex exec --approve-for-me
      -c sandbox_workspace_write.network_access=true
      --color never -o "$SUMMARY_FILE" -- "$prompt")
    ;;
  *)
    write_status unavailable "Configured agent '$agent' has no reviewed non-interactive MVP adapter"
    echo "Configured agent '$agent' has no reviewed non-interactive MVP adapter." >"$LOG_FILE"
    exit 1
    ;;
esac

(
  cd "$ROOT_DIR"
  exec setsid timeout "$MAX_SECONDS" env HOME="${HOME:?}" PATH="$AGENT_PATH" \
    "${agent_command[@]}"
) >"$LOG_FILE" 2>&1 &
AGENT_PID=$!
if wait "$AGENT_PID"; then
  AGENT_PID=
  current_state=$(jq -r '.state // empty' "$STATUS_FILE" 2>/dev/null || true)
  if [ "$current_state" != waiting-for-human ]; then
    write_status completed 'Agent finished; inspect agent-summary.md and acceptance-result.json.'
  fi
else
  code=$?
  AGENT_PID=
  if [ "$code" -eq 124 ]; then
    write_status failed "Agent timed out after $MAX_SECONDS seconds"
  else
    write_status failed "Agent exited with status $code"
  fi
  exit "$code"
fi
