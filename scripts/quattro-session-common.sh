#!/bin/sh
# Session-neutral lifecycle and evidence helpers.
# Callers provide a fixed quattro_docker() function; data never selects a command.

quattro_validate_backend() {
  case "${1:-}" in
    lab-vt|gdm-session) return 0 ;;
    *)
      echo "Unknown Quattro session backend: ${1:-empty}" >&2
      return 2
      ;;
  esac
}

quattro_require_backend() {
  actual=${1:-}
  expected=${2:-}
  quattro_validate_backend "$actual" || return
  if [ "$actual" != "$expected" ]; then
    echo "Backend $actual is not implemented by this launcher (expected $expected)." >&2
    return 2
  fi
}

quattro_validate_run_id() {
  case "${1:-}" in
    ''|*[!A-Za-z0-9_-]*)
      echo "Invalid Quattro run ID: ${1:-empty}" >&2
      return 2
      ;;
  esac
}

# GDM can change the foreground VT while collectors/containers are prepared.
# seatd uses that foreground VT, not the device name passed to Docker.
quattro_wait_for_session_vt() (
  session_id=$1
  session_uid=$2
  session_tty=$3
  evidence=$4
  attempts=0
  stable=0
  while [ "$attempts" -lt 10 ]; do
    attempts=$((attempts + 1))
    foreground=$(cat /sys/class/tty/tty0/active 2>/dev/null) || foreground=unavailable
    properties=$(timeout 1 loginctl show-session "$session_id" \
      -p User -p Active -p Remote -p Seat -p TTY -p Type 2>/dev/null) || properties=
    matched=false
    if [ "$foreground" = "$session_tty" ] &&
       printf '%s\n' "$properties" | grep -Fxq "User=$session_uid" &&
       printf '%s\n' "$properties" | grep -Fxq 'Active=yes' &&
       printf '%s\n' "$properties" | grep -Fxq 'Remote=no' &&
       printf '%s\n' "$properties" | grep -Fxq 'Seat=seat0' &&
       printf '%s\n' "$properties" | grep -Fxq 'Type=wayland' &&
       printf '%s\n' "$properties" | grep -Fxq "TTY=$session_tty"; then
      matched=true
      stable=$((stable + 1))
    else
      stable=0
    fi
    jq -cn --arg sessionId "$session_id" --arg assignedTty "$session_tty" \
      --arg foregroundTty "$foreground" --arg properties "$properties" \
      --argjson matched "$matched" --argjson attempt "$attempts" \
      '{schemaVersion:1,sessionId:$sessionId,assignedTty:$assignedTty,foregroundTty:$foregroundTty,properties:$properties,matched:$matched,attempt:$attempt,observedAt:(now|todateiso8601)}' \
      >>"$evidence" || return 1
    [ "$stable" -ge 3 ] && return 0
    sleep 0.2
  done
  echo 'Assigned GDM session did not retain the foreground VT; compositor start refused.' >&2
  return 1
)

quattro_new_run_id() {
  printf '%s-%s\n' "$(date +%Y%m%d-%H%M%S)" "$$"
}

quattro_container_label() {
  run_id=$1
  quattro_validate_run_id "$run_id" || return
  printf 'dev.omarchy-quattro.run-id=%s\n' "$run_id"
}

quattro_archive_file() {
  source_file=$1
  archive_dir=$2
  target_name=$3
  [ -f "$source_file" ] || return 0
  case "$target_name" in
    ''|*/*|.|..) echo "Invalid archive target name: $target_name" >&2; return 2 ;;
  esac
  mkdir -p "$archive_dir"
  archive_tmp="$archive_dir/.$target_name.$$"
  if ! cp "$source_file" "$archive_tmp"; then
    rm -f "$archive_tmp"
    return 1
  fi
  mv -f "$archive_tmp" "$archive_dir/$target_name"
}

quattro_write_session_record() {
  archive_dir=$1
  run_id=$2
  session_state=$3
  revision=$4
  exit_code=${5:-}
  quattro_validate_run_id "$run_id" || return
  case "$session_state" in
    preflight|ready-for-handoff|starting|ready|testing|awaiting-visual-check|passed|failed|restoring-gdm|complete) ;;
    *) echo "Invalid Quattro session state: $session_state" >&2; return 2 ;;
  esac
  if [ -n "$exit_code" ]; then
    case "$exit_code" in *[!0-9]*) echo "Invalid session exit code: $exit_code" >&2; return 2 ;; esac
  fi
  mkdir -p "$archive_dir"
  session_tmp="$archive_dir/.session.json.$$"
  if [ -n "$exit_code" ]; then
    jq -cn --arg runId "$run_id" --arg state "$session_state" --arg revision "$revision" --argjson exitCode "$exit_code" \
      '{schemaVersion:1,runId:$runId,state:$state,revision:$revision,exitCode:$exitCode,stateChangedAt:(now|todateiso8601)}' \
      >"$session_tmp" || { rm -f "$session_tmp"; return 1; }
  else
    jq -cn --arg runId "$run_id" --arg state "$session_state" --arg revision "$revision" \
      '{schemaVersion:1,runId:$runId,state:$state,revision:$revision,stateChangedAt:(now|todateiso8601)}' \
      >"$session_tmp" || { rm -f "$session_tmp"; return 1; }
  fi
  mv -f "$session_tmp" "$archive_dir/session.json"
}

quattro_capture_container() {
  container_name=$1
  archive_dir=$2
  command -v quattro_docker >/dev/null 2>&1 || {
    echo 'quattro_docker() is required by the session lifecycle module.' >&2
    return 2
  }
  quattro_docker container inspect "$container_name" >/dev/null 2>&1 || return 0
  mkdir -p "$archive_dir"
  log_tmp="$archive_dir/.$container_name.log.$$"
  inspect_tmp="$archive_dir/.$container_name.inspect.json.$$"
  if ! quattro_docker logs "$container_name" >"$log_tmp" 2>&1; then
    printf '%s\n' "docker logs returned nonzero for $container_name; output retained." >>"$log_tmp"
  fi
  if ! quattro_docker inspect "$container_name" >"$inspect_tmp"; then
    rm -f "$log_tmp" "$inspect_tmp"
    echo "Could not inspect container $container_name; leaving it untouched." >&2
    return 1
  fi
  mv -f "$log_tmp" "$archive_dir/$container_name.log"
  mv -f "$inspect_tmp" "$archive_dir/$container_name.inspect.json"
}

quattro_archive_stopped_container() {
  container_name=$1
  archive_root=$2
  fallback_run_id=$3
  command -v quattro_docker >/dev/null 2>&1 || {
    echo 'quattro_docker() is required by the session lifecycle module.' >&2
    return 2
  }
  quattro_validate_run_id "$fallback_run_id" || return
  quattro_docker container inspect "$container_name" >/dev/null 2>&1 || return 0
  container_state=$(quattro_docker container inspect -f '{{.State.Status}}' "$container_name") || return 1
  if [ "$container_state" != exited ]; then
    echo "Container $container_name is $container_state; stop it or use its existing session first." >&2
    return 1
  fi
  container_run=$(quattro_docker container inspect -f '{{index .Config.Labels "dev.omarchy-quattro.run-id"}}' "$container_name" 2>/dev/null || true)
  if ! quattro_validate_run_id "$container_run" >/dev/null 2>&1; then
    container_run=$fallback_run_id
  fi
  container_archive="$archive_root/$container_run"
  quattro_capture_container "$container_name" "$container_archive" || return
  quattro_docker rm "$container_name" >/dev/null
  echo "Archived completed $container_name logs in artifacts/quattro-runs/$container_run"
}

quattro_wait_for_path() {
  path_kind=$1
  wait_path=$2
  remaining=$3
  case "$remaining" in ''|*[!0-9]*) echo "Invalid wait timeout: $remaining" >&2; return 2 ;; esac
  while [ "$remaining" -gt 0 ]; do
    case "$path_kind" in
      file) [ -s "$wait_path" ] && return 0 ;;
      socket) [ -S "$wait_path" ] && return 0 ;;
      *) echo "Unknown wait path kind: $path_kind" >&2; return 2 ;;
    esac
    sleep 1
    remaining=$((remaining - 1))
  done
  return 1
}

quattro_stop_pid() {
  owned_pid=${1:-}
  [ -n "$owned_pid" ] || return 0
  case "$owned_pid" in *[!0-9]*) echo "Invalid owned PID: $owned_pid" >&2; return 2 ;; esac
  kill "$owned_pid" 2>/dev/null || true
  wait "$owned_pid" 2>/dev/null || true
}
