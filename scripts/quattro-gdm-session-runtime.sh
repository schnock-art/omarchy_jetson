#!/bin/sh
# Fixed runtime supervisor for the S3 GDM session service.
# This file is inert in the repository; the service accepts only a reviewed,
# root-owned installed copy at the fixed libexec path.
set -eu

CHECKOUT=/home/looco/repos/omarchy_jetson
LIBEXEC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SESSION_SCRIPTS="$CHECKOUT/scripts"
RUNTIME_ROOT=/run/omarchy-quattro/runtime
ARCHIVE_ROOT="$CHECKOUT/artifacts/quattro-runs"
HYPR_CONTAINER=hyprland-quattro-gdm
QS_CONTAINER=quickshell-quattro-gdm
HYPR_IMAGE=hyprland:phase2-runtime
QS_IMAGE=quickshell:phase1-hypr-lab
QS_BIN=/tmp/quickshell-services-build/src/quickshell
TEST_CONFIG="$CHECKOUT/tests/runtime-smoke/hyprland.conf"
TEST_ROOT="$CHECKOUT/tests/runtime-smoke"
OMARCHY_ROOT=/home/looco/omarchy
S5_FAILURE_TRIGGER=/run/omarchy-quattro/s5-failure-once.json
S5_TERMINATION_TRIGGER=/run/omarchy-quattro/s5-termination-once.json

. "$LIBEXEC_DIR/quattro-session-common.sh"
. "$LIBEXEC_DIR/quattro-session-services.sh"

quattro_docker() {
  docker "$@"
}

runtime_fail() {
  echo "Quattro GDM runtime failed: $*" >&2
  exit 2
}

runtime_require_root_file() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || runtime_fail "missing installed runtime file: $file"
  owner=$(stat -c %u "$file")
  mode=$(stat -c %a "$file")
  [ "$owner" -eq 0 ] || runtime_fail "installed runtime file is not root-owned: $file"
  case "$mode" in
    *[2367][0-7]|*[0-7][2367]) runtime_fail "installed runtime file is group/world writable: $file" ;;
  esac
}

runtime_validate_number() {
  case "$2" in ''|*[!0-9]*) runtime_fail "invalid $1" ;; esac
}

runtime_validate_tty() {
  case "$1" in tty[1-9]|tty[1-9][0-9]) ;; *) runtime_fail 'invalid assigned TTY' ;; esac
}

runtime_write_status() {
  state=$1
  exit_code=${2:-}
  archive_ready=${3:-false}
  mkdir -p "$RUN_DIR"
  chmod 0700 "$RUN_DIR"
  status_tmp="$RUN_DIR/.status.json.$$"
  if [ -n "$exit_code" ]; then
    jq -cn --arg runId "$RUN_ID" --arg state "$state" --argjson supervisorPid "$$" \
      --argjson exitCode "$exit_code" --argjson archiveReady "$archive_ready" \
      '{schemaVersion:1,runId:$runId,state:$state,supervisorPid:$supervisorPid,exitCode:$exitCode,archiveReady:$archiveReady,updatedAt:(now|todateiso8601)}' \
      >"$status_tmp"
  else
    jq -cn --arg runId "$RUN_ID" --arg state "$state" --argjson supervisorPid "$$" \
      --argjson archiveReady "$archive_ready" \
      '{schemaVersion:1,runId:$runId,state:$state,supervisorPid:$supervisorPid,archiveReady:$archiveReady,updatedAt:(now|todateiso8601)}' \
      >"$status_tmp"
  fi
  chmod 0600 "$status_tmp"
  mv -f "$status_tmp" "$RUN_DIR/status.json"
}

runtime_owned_container() {
  name=$1
  quattro_docker container inspect "$name" >/dev/null 2>&1 || return 1
  owner=$(quattro_docker container inspect -f '{{index .Config.Labels "dev.omarchy-quattro.run-id"}}' "$name" 2>/dev/null || true)
  [ "$owner" = "$RUN_ID" ]
}

runtime_reject_existing_container() {
  name=$1
  if quattro_docker container inspect "$name" >/dev/null 2>&1; then
    runtime_fail "fixed container already exists: $name"
  fi
}

runtime_archive() {
  archive_failed=0
  mkdir -p "$ARCHIVE_DIR"
  quattro_archive_file "$RUN_DIR/seat-check.jsonl" "$ARCHIVE_DIR" seat-check.jsonl || archive_failed=1
  quattro_archive_file "$RUN_DIR/supervisor.log" "$ARCHIVE_DIR" supervisor.log || archive_failed=1
  quattro_archive_file "$RUN_DIR/failure-injection.json" "$ARCHIVE_DIR" failure-injection.json || archive_failed=1
  quattro_archive_file "$RUN_DIR/termination-injection.json" "$ARCHIVE_DIR" termination-injection.json || archive_failed=1
  quattro_services_archive "$ARCHIVE_DIR" || archive_failed=1
  quattro_archive_file "$CHECKOUT/artifacts/workloads/registry.json" "$ARCHIVE_DIR" workload-registry.json || archive_failed=1
  if runtime_owned_container "$QS_CONTAINER"; then
    quattro_capture_container "$QS_CONTAINER" "$ARCHIVE_DIR" || archive_failed=1
    # The evaluator's acceptance contract predates the GDM-specific container
    # names. Preserve those canonical evidence names without changing the
    # source container identity recorded alongside them.
    quattro_archive_file "$ARCHIVE_DIR/$QS_CONTAINER.log" "$ARCHIVE_DIR" quickshell-quattro-smoke.log || archive_failed=1
  fi
  if runtime_owned_container "$HYPR_CONTAINER"; then
    quattro_capture_container "$HYPR_CONTAINER" "$ARCHIVE_DIR" || archive_failed=1
    quattro_archive_file "$ARCHIVE_DIR/$HYPR_CONTAINER.log" "$ARCHIVE_DIR" hyprland-phase2-drm.log || archive_failed=1
  fi
  quattro_archive_file "$CHECKOUT/mvp/acceptance.json" "$ARCHIVE_DIR" acceptance-manifest.json || archive_failed=1
  revision=$(git -C "$CHECKOUT" rev-parse HEAD 2>/dev/null || echo unavailable)
  final_state=awaiting-visual-check
  [ "$RESULT" -eq 0 ] || final_state=failed
  quattro_write_session_record "$ARCHIVE_DIR" "$RUN_ID" "$final_state" "$revision" "$RESULT" || archive_failed=1
  chown -R "$HOST_UID:$HOST_GID" "$ARCHIVE_DIR" || archive_failed=1
  [ "$archive_failed" -eq 0 ]
}

runtime_remove_owned_container() {
  name=$1
  runtime_owned_container "$name" || return 0
  state=$(quattro_docker container inspect -f '{{.State.Status}}' "$name")
  [ "$state" = exited ] || return 1
  quattro_docker rm "$name" >/dev/null
}

runtime_consume_s5_failure_trigger() {
  [ -e "$S5_FAILURE_TRIGGER" ] || return 0
  [ -f "$S5_FAILURE_TRIGGER" ] && [ ! -L "$S5_FAILURE_TRIGGER" ] || runtime_fail 'unsafe S5 failure trigger'
  [ "$(stat -c %u "$S5_FAILURE_TRIGGER")" -eq 0 ] || runtime_fail 'S5 failure trigger is not root-owned'
  case "$(stat -c %a "$S5_FAILURE_TRIGGER")" in *[2367][0-7]|*[0-7][2367]) runtime_fail 'S5 failure trigger is writable by another user' ;; esac
  mv "$S5_FAILURE_TRIGGER" "$RUN_DIR/failure-injection.json"
  jq -e 'keys == ["armedAt","failure","schemaVersion"] and .schemaVersion == 1 and .failure == "preflight-v1" and (.armedAt | type == "string")' "$RUN_DIR/failure-injection.json" >/dev/null || runtime_fail 'invalid S5 failure trigger'
  runtime_fail 'S5 controlled preflight failure requested'
}

runtime_consume_s5_termination_trigger() {
  [ -e "$S5_TERMINATION_TRIGGER" ] || return 0
  [ -f "$S5_TERMINATION_TRIGGER" ] && [ ! -L "$S5_TERMINATION_TRIGGER" ] || runtime_fail 'unsafe S5 termination trigger'
  [ "$(stat -c %u "$S5_TERMINATION_TRIGGER")" -eq 0 ] || runtime_fail 'S5 termination trigger is not root-owned'
  case "$(stat -c %a "$S5_TERMINATION_TRIGGER")" in *[2367][0-7]|*[0-7][2367]) runtime_fail 'S5 termination trigger is writable by another user' ;; esac
  mv "$S5_TERMINATION_TRIGGER" "$RUN_DIR/termination-injection.json"
  jq -e 'keys == ["armedAt","failure","schemaVersion"] and .schemaVersion == 1 and .failure == "terminate-after-ready-v1" and (.armedAt | type == "string")' "$RUN_DIR/termination-injection.json" >/dev/null || runtime_fail 'invalid S5 termination trigger'
  quattro_docker stop --time 5 "$HYPR_CONTAINER" >/dev/null || runtime_fail 'S5 controlled termination could not stop Hyprland'
  runtime_fail 'S5 controlled post-ready termination requested'
}

runtime_cleanup() {
  RESULT=$?
  trap - EXIT HUP INT TERM
  if runtime_owned_container "$QS_CONTAINER"; then
    quattro_docker stop --time 3 "$QS_CONTAINER" >/dev/null 2>&1 || true
  fi
  if runtime_owned_container "$HYPR_CONTAINER"; then
    quattro_docker stop --time 5 "$HYPR_CONTAINER" >/dev/null 2>&1 || true
  fi
  quattro_services_stop
  archive_ready=false
  if runtime_archive; then
    archive_ready=true
    runtime_remove_owned_container "$QS_CONTAINER" || archive_ready=false
    runtime_remove_owned_container "$HYPR_CONTAINER" || archive_ready=false
    if [ -n "$RUNTIME_VOLUME" ]; then
      quattro_docker volume rm "$RUNTIME_VOLUME" >/dev/null 2>&1 || archive_ready=false
    fi
  else
    RESULT=1
  fi
  terminal=stopped
  [ "$RESULT" -eq 0 ] || terminal=failed
  runtime_write_status "$terminal" "$RESULT" "$archive_ready"
  exit "$RESULT"
}

runtime_preflight() {
  [ "$(id -u)" -eq 0 ] || runtime_fail 'runtime supervisor must run as root'
  runtime_require_root_file "$LIBEXEC_DIR/quattro-session-common.sh"
  runtime_require_root_file "$LIBEXEC_DIR/quattro-session-services.sh"
  [ -r "$TEST_CONFIG" ] && [ -d "$TEST_ROOT" ] && [ -d "$OMARCHY_ROOT/shell" ] || runtime_fail 'fixed runtime inputs are unavailable'
  [ -c "/dev/$SESSION_TTY" ] && [ -c /dev/tty0 ] && [ -d /dev/dri ] && [ -d /dev/input ] || runtime_fail 'assigned seat devices are unavailable'
  [ -S "/run/user/$HOST_UID/bus" ] && [ -S "/run/user/$HOST_UID/pipewire-0" ] || runtime_fail 'user runtime sockets are unavailable'
  command -v docker >/dev/null
  docker info >/dev/null
  docker image inspect "$HYPR_IMAGE" >/dev/null
  docker image inspect "$QS_IMAGE" >/dev/null
  runtime_reject_existing_container "$HYPR_CONTAINER"
  runtime_reject_existing_container "$QS_CONTAINER"
}

runtime_supervise() {
  RUN_ID=$1
  SESSION_ID=$2
  HOST_UID=$3
  HOST_GID=$4
  SESSION_TTY=$5
  quattro_validate_run_id "$RUN_ID"
  case "$SESSION_ID" in ''|*[!A-Za-z0-9_-]*) runtime_fail 'invalid session ID' ;; esac
  runtime_validate_number UID "$HOST_UID"
  runtime_validate_number GID "$HOST_GID"
  runtime_validate_tty "$SESSION_TTY"
  RUN_DIR="$RUNTIME_ROOT/$RUN_ID"
  ARCHIVE_DIR="$ARCHIVE_ROOT/$RUN_ID"
  RESULT=1
  RUNTIME_VOLUME=
  mkdir -p "$RUNTIME_ROOT"
  chmod 0700 "$RUNTIME_ROOT"
  runtime_write_status starting
  quattro_services_init
  trap runtime_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM

  runtime_consume_s5_failure_trigger
  runtime_preflight
  HOST_USER=$(getent passwd "$HOST_UID" | cut -d: -f1)
  [ -n "$HOST_USER" ] || runtime_fail 'session user is unavailable'
  INPUT_GID=$(getent group input | cut -d: -f3)
  VIDEO_GID=$(getent group video | cut -d: -f3)
  RENDER_GID=$(getent group render | cut -d: -f3)
  [ -n "$INPUT_GID" ] && [ -n "$VIDEO_GID" ] && [ -n "$RENDER_GID" ] || runtime_fail 'required device groups are unavailable'
  HOST_AGENT_PATH="/home/$HOST_USER/omarchy/bin:/usr/lib/chatgpt/resources:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  setpriv --reuid="$HOST_UID" --regid="$HOST_GID" --init-groups "$SESSION_SCRIPTS/quattro-workloads.sh" init
  quattro_services_start "$SESSION_SCRIPTS" "$HOST_USER" "$HOST_UID" "$HOST_GID" \
    "$HOST_AGENT_PATH" "$QS_IMAGE" "$QS_BIN" "$RUN_ID"

  CONTAINER_LABEL=$(quattro_container_label "$RUN_ID")
  RUNTIME_VOLUME="jetson-gdm-wayland-$RUN_ID"
  quattro_docker volume create "$RUNTIME_VOLUME" >/dev/null
  DBUS_SOCKET="/run/user/$HOST_UID/bus"
  PW_SOCKET="/run/user/$HOST_UID/pipewire-0"
  JETSON_POWER_MODE=$(timeout 5 nvpmodel -q 2>/dev/null || echo 'NVIDIA power mode unavailable')
  # All mounts, devices, images, commands, and environment names are fixed here.
  # Only validated run/session identity values enter labels and ownership fields.
  # shellcheck disable=SC2086
  quattro_docker run -d --name "$QS_CONTAINER" --label "$CONTAINER_LABEL" \
    --network none --runtime=nvidia --gpus all --device=/dev/dri \
    --user "$HOST_UID:$HOST_GID" --group-add "$VIDEO_GID" --group-add "$RENDER_GID" \
    --mount "type=volume,src=$RUNTIME_VOLUME,dst=/tmp/hypr-runtime" \
    --mount "type=bind,src=$TEST_ROOT,dst=/test,readonly" \
    --mount "type=bind,src=$OMARCHY_ROOT,dst=/omarchy,readonly" \
    --security-opt apparmor=unconfined \
    --mount "type=bind,src=$DBUS_SOCKET,dst=/tmp/host-session-bus,readonly" \
    --mount "type=bind,src=$PW_SOCKET,dst=/tmp/host-pipewire,readonly" \
    $QS_SYSTEM_ARGS $QS_TELEMETRY_ARGS $QS_AGENT_STATUS_ARGS $QS_ACTION_ARGS \
    --mount "type=bind,src=$CHECKOUT/artifacts/workloads,dst=/tmp/jetson-workloads,readonly" \
    -e HOME=/tmp -e XDG_RUNTIME_DIR=/tmp/hypr-runtime -e QS_BIN="$QS_BIN" \
    -e OMARCHY_PATH=/omarchy -e QML_IMPORT_PATH=/omarchy/shell \
    -e DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/host-session-bus \
    -e PIPEWIRE_REMOTE=/tmp/host-pipewire -e JETSON_POWER_MODE="$JETSON_POWER_MODE" \
    -e LANG=C.UTF-8 -e QT_QPA_PLATFORM=wayland \
    --mount type=bind,src=/etc/localtime,dst=/etc/localtime,readonly \
    --entrypoint sh "$QS_IMAGE" /test/run-quattro-shell.sh >/dev/null

  quattro_wait_for_session_vt "$SESSION_ID" "$HOST_UID" "$SESSION_TTY" "$RUN_DIR/seat-check.jsonl" || runtime_fail 'GDM seat/VT readiness failed'
  quattro_docker run -d -t --name "$HYPR_CONTAINER" --label "$CONTAINER_LABEL" \
    --network none --runtime=nvidia --gpus all --device=/dev/dri --device=/dev/input \
    --device-cgroup-rule='c 13:* rwm' --mount type=bind,src=/run/udev,dst=/run/udev,readonly \
    --mount "type=bind,src=$TEST_CONFIG,dst=/etc/hyprland-smoke.conf,readonly" \
    --mount "type=volume,src=$RUNTIME_VOLUME,dst=/tmp/hypr-runtime" \
    --device=/dev/tty0 --device="/dev/$SESSION_TTY" --cap-add=SYS_TTY_CONFIG \
    -e QUATTRO_SEATD_UNBOUND=1 \
    -e HYPRLAND_UID="$HOST_UID" -e HYPRLAND_GID="$HOST_GID" \
    -e HYPRLAND_INPUT_GID="$INPUT_GID" -e HYPRLAND_VIDEO_GID="$VIDEO_GID" \
    -e HYPRLAND_RENDER_GID="$RENDER_GID" -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
    "$HYPR_IMAGE" --config /etc/hyprland-smoke.conf >/dev/null

  quattro_docker container inspect -f '{{.State.Running}}' "$HYPR_CONTAINER" | grep -qx true
  quattro_docker container inspect -f '{{.State.Running}}' "$QS_CONTAINER" | grep -qx true
  runtime_write_status ready
  runtime_consume_s5_termination_trigger
  RESULT=$(quattro_docker wait "$HYPR_CONTAINER")
  runtime_validate_number 'Hyprland exit status' "$RESULT"
  exit "$RESULT"
}

[ "$#" -eq 6 ] || runtime_fail 'expected fixed supervise operation and five identity values'
[ "$1" = supervise ] || runtime_fail 'unknown runtime operation'
shift
runtime_supervise "$@"
