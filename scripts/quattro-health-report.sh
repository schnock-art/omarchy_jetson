#!/usr/bin/env bash
# Read-only Quattro lab health report. Safe to run over SSH.
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE_DIR="$ROOT_DIR/artifacts/quattro-runs"
REPORT_DIR="$ROOT_DIR/artifacts/quattro-health"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/$(date +%Y%m%d-%H%M%S)-health.txt"
# Keep the live terminal output and save an exact copy for later inspection.
exec > >(tee "$REPORT_FILE")
REQUIRE_RUN=0

usage() {
  echo "Usage: $0 [--require-run]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-run) REQUIRE_RUN=1; shift ;;
    *) usage ;;
  esac
done

PASS=0
WARN=0
FAIL=0
DOCKER_OK=0
QS_STATE=
HYPR_STATE=
QS_LOG=
HYPR_LOG=
AGENT_STATUS_FILE=

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$*"; }
warn() { WARN=$((WARN + 1)); printf 'WARN  %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

docker_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    docker "$@"
  else
    sudo -n docker "$@"
  fi
}

container_state() {
  docker_cmd inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true
}

container_exit() {
  docker_cmd inspect -f '{{.State.ExitCode}}' "$1" 2>/dev/null || true
}

container_logs() {
  docker_cmd logs "$1" 2>&1 || true
}

latest_archive() {
  find "$ARCHIVE_DIR" -mindepth 2 -maxdepth 2 -type f -name 'quickshell-quattro-smoke.log' \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | sed -n '1{s/^[^ ]* //;p;}'
}

agent_status_from_inspect() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
item = data[0] if isinstance(data, list) else data
for mount in item.get("Mounts", []):
    if mount.get("Destination") == "/tmp/jetson-agent-status":
        print(mount.get("Source", ""))
        break
PY
}

printf 'Quattro Jetson lab health report\n'
printf 'Repository: %s\n' "$ROOT_DIR"
printf 'Revision:   %s\n' "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unavailable)"
printf 'Saved report: %s\n' "$REPORT_FILE"
printf '\nInfrastructure\n'

if docker_cmd info >/dev/null 2>&1; then
  DOCKER_OK=1
  pass 'Docker daemon is reachable'
else
  fail 'Docker daemon is not reachable (try the report again with working sudo access)'
fi

if [ -x "$ROOT_DIR/scripts/start-quattro-lab.sh" ] && [ -x "$ROOT_DIR/scripts/run-hyprland-drm.sh" ]; then
  pass 'Launcher scripts are present and executable'
else
  fail 'Launcher scripts are missing or not executable'
fi

if [ -f "$ROOT_DIR/tests/runtime-smoke/jetson-telemetry/Panel.qml" ] && \
   [ -x "$ROOT_DIR/scripts/collect-jetson-telemetry.sh" ]; then
  pass 'Jetson telemetry integration is present'
else
  fail 'Jetson telemetry integration is incomplete'
fi

if [ "$DOCKER_OK" -eq 1 ]; then
  if docker_cmd image inspect hyprland:phase2-runtime >/dev/null 2>&1 && \
     docker_cmd image inspect quickshell:phase1-hypr-lab >/dev/null 2>&1; then
    pass 'Required ARM64 lab images are present'
  else
    fail 'One or more required lab images are missing'
  fi

  QS_STATE=$(container_state quickshell-quattro-smoke)
  HYPR_STATE=$(container_state hyprland-phase2-drm)
  if [ -n "$QS_STATE" ] || [ -n "$HYPR_STATE" ]; then
    printf '\nCurrent run\n'
    note "quickshell-quattro-smoke: ${QS_STATE:-absent}"
    note "hyprland-phase2-drm:    ${HYPR_STATE:-absent}"
  else
    warn 'No current Quattro containers are present'
  fi

  if [ "$QS_STATE" = running ]; then
    QS_LOG=$(container_logs quickshell-quattro-smoke)
  elif [ -n "$QS_STATE" ]; then
    QS_LOG=$(container_logs quickshell-quattro-smoke)
  fi
  if [ "$HYPR_STATE" = running ] || [ -n "$HYPR_STATE" ]; then
    HYPR_LOG=$(container_logs hyprland-phase2-drm)
  fi
fi

ARCHIVE_LOG=$(latest_archive)
if [ -n "$ARCHIVE_LOG" ]; then
  ARCHIVE_RUN_DIR=$(dirname "$ARCHIVE_LOG")
  pass 'A retained Quattro run archive is available'
  note "$ARCHIVE_LOG"
elif [ "$REQUIRE_RUN" -eq 1 ]; then
  fail 'No retained Quattro run archive was found'
else
  warn 'No retained Quattro run archive was found yet'
fi

if [ "$DOCKER_OK" -eq 1 ] && [ -n "$QS_STATE" ]; then
  AGENT_STATUS_DIR=$(docker_cmd inspect -f '{{range .Mounts}}{{if eq .Destination "/tmp/jetson-agent-status"}}{{.Source}}{{end}}{{end}}' quickshell-quattro-smoke 2>/dev/null || true)
elif [ -n "${ARCHIVE_RUN_DIR:-}" ] && [ -f "$ARCHIVE_RUN_DIR/quickshell-quattro-smoke.inspect.json" ]; then
  AGENT_STATUS_DIR=$(agent_status_from_inspect "$ARCHIVE_RUN_DIR/quickshell-quattro-smoke.inspect.json" 2>/dev/null || true)
else
  AGENT_STATUS_DIR=
fi
if [ -n "$AGENT_STATUS_DIR" ]; then AGENT_STATUS_FILE="$AGENT_STATUS_DIR/status.json"; fi

printf '\nAgent bridge\n'
if [ -f "$AGENT_STATUS_FILE" ] && jq -e . "$AGENT_STATUS_FILE" >/dev/null 2>&1; then
  codex_id=$(jq -r '.codex.id // empty' "$AGENT_STATUS_FILE")
  codex_today=$(jq -r '.codex.todayPrompts // empty' "$AGENT_STATUS_FILE")
  if [ "$codex_id" = codex ] && [ -n "$codex_today" ]; then
    pass "Codex record mounted ($codex_today prompts today)"
  else
    fail 'Agent bridge mounted but has no Codex usage record'
  fi
elif [ -n "$AGENT_STATUS_FILE" ]; then
  fail "Agent status file is missing or invalid: $AGENT_STATUS_FILE"
else
  warn 'No agent-status mount was found (run predates the agent bridge)'
fi

if [ -n "$QS_STATE" ] || [ -n "$ARCHIVE_LOG" ]; then
  if [ -z "$QS_LOG" ] && [ -n "$ARCHIVE_LOG" ]; then
    QS_LOG=$(cat "$ARCHIVE_LOG" 2>/dev/null || true)
  fi
  printf '\nQuickshell milestones\n'
  for marker in \
    'Configuration Loaded' \
    'Hyprland event socket connected' \
    'Connection established' \
    'Registered notification server with dbus.' \
    'JETSON_POWER_PANEL_LOADED'; do
    if printf '%s\n' "$QS_LOG" | grep -Fq "$marker"; then
      pass "$marker"
    else
      fail "Missing Quickshell milestone: $marker"
    fi
  done

  if printf '%s\n' "$QS_LOG" | grep -Eiq 'service plugin load failed|Failed to load configuration|ERROR:'; then
    fail 'Quickshell log contains an error or service-plugin failure'
    note 'Review the retained log shown above or the archive path.'
  else
    pass 'No fatal Quickshell/plugin error markers found'
  fi

  if printf '%s\n' "$QS_LOG" | grep -Fq 'Wayland connection broke'; then
    if [ "$QS_STATE" = exited ] || [ -z "$QS_STATE" ]; then
      pass 'Wayland disconnect occurred during normal shell shutdown'
    else
      warn 'Wayland disconnect is present while Quickshell is still marked running'
    fi
  else
    warn 'No Wayland shutdown marker found (normal for an active run)'
  fi
fi

if [ -n "$HYPR_STATE" ] || [ -n "$ARCHIVE_LOG" ]; then
  printf '\nHyprland result\n'
  HYPR_EXIT=$(container_exit hyprland-phase2-drm)
  if [ "$HYPR_STATE" = running ]; then
    pass 'Hyprland container is running'
  elif [ "$HYPR_EXIT" = 0 ] || [ -z "$HYPR_EXIT" ]; then
    pass 'Hyprland exited cleanly (or is represented only by the archive)'
  else
    fail "Hyprland container exit code: ${HYPR_EXIT:-unknown}"
  fi
  # Hyprland disables most renderer stdout after startup in this smoke config;
  # visible rendering is a physical acceptance check, not a reliable log grep.
  if printf '%s\n' "$HYPR_LOG" | grep -Fq 'New client connected'; then
    pass 'Hyprland seat accepted a client'
  fi
fi

printf '\nSummary: %s pass, %s warn, %s fail\n' "$PASS" "$WARN" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
if [ "$REQUIRE_RUN" -eq 1 ] && [ "$WARN" -gt 0 ]; then
  exit 2
fi
exit 0
