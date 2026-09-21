#!/bin/sh
# Own the fixed host-side services shared by every future Quattro backend.
# The display backend remains responsible for its compositor, seat, and VT.

quattro_services_init() {
  SYSTEM_PROXY_PID=
  TELEMETRY_PID=
  AGENT_STATUS_PID=
  ACTION_GATEWAY_PID=
  SYSTEM_PROXY_DIR=
  TELEMETRY_DIR=
  AGENT_STATUS_DIR=
  ACTION_GATEWAY_DIR=
  QS_SYSTEM_ARGS=
  QS_TELEMETRY_ARGS=
  QS_AGENT_STATUS_ARGS=
  QS_ACTION_ARGS=
}

quattro_services_are_idle() {
  [ -z "$SYSTEM_PROXY_PID" ] &&
    [ -z "$TELEMETRY_PID" ] &&
    [ -z "$AGENT_STATUS_PID" ] &&
    [ -z "$ACTION_GATEWAY_PID" ]
}

quattro_services_stop() {
  if [ -n "$ACTION_GATEWAY_PID" ]; then
    quattro_stop_pid "$ACTION_GATEWAY_PID"
    ACTION_GATEWAY_PID=
  fi
  if [ -n "$AGENT_STATUS_PID" ]; then
    quattro_stop_pid "$AGENT_STATUS_PID"
    AGENT_STATUS_PID=
  fi
  if [ -n "$TELEMETRY_PID" ]; then
    quattro_stop_pid "$TELEMETRY_PID"
    TELEMETRY_PID=
  fi
  if [ -n "$SYSTEM_PROXY_PID" ]; then
    quattro_stop_pid "$SYSTEM_PROXY_PID"
    SYSTEM_PROXY_PID=
  fi
}

quattro_services_archive() {
  services_archive_dir=$1
  services_archive_failed=0
  quattro_archive_file "$AGENT_STATUS_DIR/status.json" "$services_archive_dir" agent-status.json || services_archive_failed=1
  quattro_archive_file "$TELEMETRY_DIR/telemetry.json" "$services_archive_dir" telemetry.json || services_archive_failed=1
  quattro_archive_file "$ACTION_GATEWAY_DIR/action-status.json" "$services_archive_dir" action-status.json || services_archive_failed=1
  quattro_archive_file "$ACTION_GATEWAY_DIR/mvp-status.json" "$services_archive_dir" mvp-status.json || services_archive_failed=1
  quattro_archive_file "$ACTION_GATEWAY_DIR/gateway.log" "$services_archive_dir" action-gateway.log || services_archive_failed=1
  quattro_archive_file "$ACTION_GATEWAY_DIR/launcher.log" "$services_archive_dir" action-launcher.log || services_archive_failed=1
  [ "$services_archive_failed" -eq 0 ]
}

quattro_services_start() {
  services_script_dir=$1
  services_host_user=$2
  services_host_uid=$3
  services_host_gid=$4
  services_agent_path=$5
  services_qs_image=$6
  services_qs_bin=$7
  services_run_id=$8
  services_wait=${QUATTRO_SERVICE_READY_TIMEOUT:-5}

  quattro_services_are_idle || {
    echo 'Quattro session services already own a process.' >&2
    return 1
  }
  quattro_validate_run_id "$services_run_id" || return
  case "$services_host_user" in ''|*[!A-Za-z0-9_-]*) echo 'Invalid service user.' >&2; return 2 ;; esac
  case "$services_host_uid" in ''|*[!0-9]*) echo 'Invalid service UID.' >&2; return 2 ;; esac
  case "$services_host_gid" in ''|*[!0-9]*) echo 'Invalid service GID.' >&2; return 2 ;; esac
  case "$services_wait" in ''|*[!0-9]*) echo 'Invalid service readiness timeout.' >&2; return 2 ;; esac
  command -v xdg-dbus-proxy >/dev/null
  command -v setpriv >/dev/null
  [ -x "$services_script_dir/collect-jetson-telemetry.sh" ] || {
    echo "Telemetry collector is missing or not executable: $services_script_dir/collect-jetson-telemetry.sh" >&2
    return 1
  }
  [ -x "$services_script_dir/collect-jetson-agent-status.sh" ] || return 1
  [ -x "$services_script_dir/quattro-action-gateway.sh" ] || return 1

  SYSTEM_PROXY_DIR=$(mktemp -d /tmp/jetson-system-bus.XXXXXX)
  chown "$services_host_uid:$services_host_gid" "$SYSTEM_PROXY_DIR"
  setpriv --reuid="$services_host_uid" --regid="$services_host_gid" --init-groups \
    sh "$services_script_dir/system-bus-readonly.sh" "$SYSTEM_PROXY_DIR/bus" \
    >"$SYSTEM_PROXY_DIR/proxy.log" 2>&1 &
  SYSTEM_PROXY_PID=$!
  quattro_wait_for_path socket "$SYSTEM_PROXY_DIR/bus" "$services_wait" || {
    echo "System bus proxy failed: $SYSTEM_PROXY_DIR/proxy.log" >&2
    return 1
  }
  kill -0 "$SYSTEM_PROXY_PID" 2>/dev/null || {
    echo "System bus proxy exited during startup: $SYSTEM_PROXY_DIR/proxy.log" >&2
    return 1
  }
  QS_SYSTEM_ARGS="--mount type=bind,src=$SYSTEM_PROXY_DIR/bus,dst=/tmp/host-system-bus,readonly -e DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/host-system-bus"
  # Same read-only system-service probe as the lab backend. quattro_docker is
  # a fixed host function; no request data selects a command or argument.
  # shellcheck disable=SC2086
  quattro_docker run --rm --network none --security-opt apparmor=unconfined \
    --user "$services_host_uid:$services_host_gid" $QS_SYSTEM_ARGS \
    --mount "type=bind,src=$services_script_dir/../tests/runtime-smoke,dst=/test,readonly" \
    -e HOME=/tmp -e LANG=C.UTF-8 -e XDG_RUNTIME_DIR=/tmp/probe-runtime \
    -e QT_QPA_PLATFORM=offscreen -e QS_BIN="$services_qs_bin" \
    --entrypoint sh "$services_qs_image" -c \
    'mkdir -m 700 /tmp/probe-runtime; timeout 15 "$QS_BIN" --no-color -p /test/system-services-probe.qml' || return 1

  TELEMETRY_DIR=$(mktemp -d /tmp/jetson-telemetry.XXXXXX)
  chown "$services_host_uid:$services_host_gid" "$TELEMETRY_DIR"
  setpriv --reuid="$services_host_uid" --regid="$services_host_gid" --init-groups \
    "$services_script_dir/collect-jetson-telemetry.sh" "$TELEMETRY_DIR/telemetry.json" \
    >"$TELEMETRY_DIR/collector.log" 2>&1 &
  TELEMETRY_PID=$!
  quattro_wait_for_path file "$TELEMETRY_DIR/telemetry.json" "$services_wait" || {
    echo "Telemetry collector failed: $TELEMETRY_DIR/collector.log" >&2
    return 1
  }
  kill -0 "$TELEMETRY_PID" 2>/dev/null || {
    echo "Telemetry collector exited during startup: $TELEMETRY_DIR/collector.log" >&2
    return 1
  }
  QS_TELEMETRY_ARGS="--mount type=bind,src=$TELEMETRY_DIR,dst=/tmp/jetson-telemetry,readonly"

  AGENT_STATUS_DIR=$(mktemp -d /tmp/jetson-agent-status.XXXXXX)
  chown "$services_host_uid:$services_host_gid" "$AGENT_STATUS_DIR"
  setpriv --reuid="$services_host_uid" --regid="$services_host_gid" --init-groups \
    env HOME="/home/$services_host_user" XDG_STATE_HOME="/home/$services_host_user/.local/state" PATH="$services_agent_path" \
    "$services_script_dir/collect-jetson-agent-status.sh" "$AGENT_STATUS_DIR/status.json" \
    >"$AGENT_STATUS_DIR/collector.log" 2>&1 &
  AGENT_STATUS_PID=$!
  quattro_wait_for_path file "$AGENT_STATUS_DIR/status.json" "$services_wait" || {
    echo "Agent status bridge failed: $AGENT_STATUS_DIR/collector.log" >&2
    return 1
  }
  kill -0 "$AGENT_STATUS_PID" 2>/dev/null || {
    echo "Agent status bridge exited during startup: $AGENT_STATUS_DIR/collector.log" >&2
    return 1
  }
  QS_AGENT_STATUS_ARGS="--mount type=bind,src=$AGENT_STATUS_DIR,dst=/tmp/jetson-agent-status,readonly"

  ACTION_GATEWAY_DIR=$(mktemp -d /tmp/jetson-action-gateway.XXXXXX)
  chown "$services_host_uid:$services_host_gid" "$ACTION_GATEWAY_DIR"
  chmod 0700 "$ACTION_GATEWAY_DIR"
  setpriv --reuid="$services_host_uid" --regid="$services_host_gid" --init-groups \
    env HOME="/home/$services_host_user" XDG_STATE_HOME="/home/$services_host_user/.local/state" PATH="$services_agent_path" \
    "$services_script_dir/quattro-action-gateway.sh" "$ACTION_GATEWAY_DIR" "$AGENT_STATUS_DIR/status.json" "$services_run_id" \
    >"$ACTION_GATEWAY_DIR/launcher.log" 2>&1 &
  ACTION_GATEWAY_PID=$!
  sleep 1
  kill -0 "$ACTION_GATEWAY_PID" 2>/dev/null || {
    echo "Action gateway failed: $ACTION_GATEWAY_DIR/launcher.log" >&2
    return 1
  }
  # This remains the sole writable host mount presented to Quickshell.
  QS_ACTION_ARGS="--mount type=bind,src=$ACTION_GATEWAY_DIR,dst=/tmp/jetson-actions"
}
