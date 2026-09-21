#!/bin/sh
# Run this from the Jetson's active physical VT, not over SSH.
set -eu

STOP_GDM=0
CHECK_ONLY=0
PANEL=0
QUATTRO=0
ACTIVE_TTY=
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_CONFIG="$SCRIPT_DIR/../tests/runtime-smoke/hyprland.conf"
RUN_ID=${QUATTRO_RUN_ID:-$(date +%Y%m%d-%H%M%S)}
SESSION_ARCHIVE_DIR="$SCRIPT_DIR/../artifacts/quattro-runs/$RUN_ID"
case "$RUN_ID" in *[!A-Za-z0-9_-]*|'') echo "Invalid Quattro run ID: $RUN_ID" >&2; exit 2 ;; esac
"$SCRIPT_DIR/check-syntax.sh"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --stop-gdm) STOP_GDM=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --panel) PANEL=1; shift ;;
    --quattro) QUATTRO=1; shift ;;
    --tty) [ "$#" -ge 2 ] || exit 2; ACTIVE_TTY=$2; shift 2 ;;
    *) echo "Usage: $0 [--stop-gdm] [--panel|--quattro] [--check] [--tty /dev/ttyN]" >&2; exit 2 ;;
  esac
done
[ "$PANEL" -eq 0 ] || [ "$QUATTRO" -eq 0 ] || { echo "Choose --panel or --quattro, not both." >&2; exit 2; }

# Capture the original console BEFORE sudo creates its own pseudo-terminal.
ACTIVE_TTY=${ACTIVE_TTY:-${SUDO_TTY:-$(tty 2>/dev/null || true)}}
VT_NUMBER=${ACTIVE_TTY#/dev/tty}
case "$VT_NUMBER" in
  ''|0|*[!0-9]*)
    echo "Cannot resolve a physical VT (detected: $ACTIVE_TTY)." >&2
    echo "On the local text console run this script without sudo, or pass --tty /dev/tty3 if that is your console." >&2
    exit 1 ;;
esac
[ "$ACTIVE_TTY" = "/dev/tty$VT_NUMBER" ] || exit 1
[ "$VT_NUMBER" -le 63 ] || exit 1

case "$(id -u)" in
  0) ;;
  *)
    set -- --tty "$ACTIVE_TTY"
    [ "$STOP_GDM" -eq 0 ] || set -- "$@" --stop-gdm
    [ "$CHECK_ONLY" -eq 0 ] || set -- "$@" --check
    [ "$PANEL" -eq 0 ] || set -- "$@" --panel
    [ "$QUATTRO" -eq 0 ] || set -- "$@" --quattro
    # sudo normally drops caller-provided environment variables. Pass the
    # validated ID explicitly so preflight, runtime services, and archival all
    # refer to one evidence bundle across the privilege transition.
    exec sudo -- env QUATTRO_RUN_ID="$RUN_ID" "$(readlink -f "$0")" "$@" ;;
esac

HOST_USER=looco
HOST_UID=$(id -u "$HOST_USER")
HOST_GID=$(id -g "$HOST_USER")
HOST_AGENT_PATH="/home/$HOST_USER/omarchy/bin:/usr/lib/chatgpt/resources:$PATH"
INPUT_GID=$(getent group input | cut -d: -f3)
VIDEO_GID=$(getent group video | cut -d: -f3)
RENDER_GID=$(getent group render | cut -d: -f3)

[ -n "$INPUT_GID" ] && [ -n "$VIDEO_GID" ] && [ -n "$RENDER_GID" ]
[ -d /run/udev/data ] || { echo "/run/udev/data is unavailable; host udev is required." >&2; exit 1; }
[ -c /dev/tty0 ] && [ -c "$ACTIVE_TTY" ] && [ -d /dev/dri ] && [ -d /dev/input ]
docker info >/dev/null
docker image inspect hyprland:phase2-runtime >/dev/null
[ -r "$TEST_CONFIG" ] || { echo "Missing test config: $TEST_CONFIG" >&2; exit 1; }
command -v chvt >/dev/null
command -v fgconsole >/dev/null
if [ "$PANEL" -eq 1 ] || [ "$QUATTRO" -eq 1 ]; then
  docker image inspect quickshell:phase1 >/dev/null
  QS_CONTAINER=quickshell-layer-smoke
  QS_RUNNER=/test/run-layer-panel.sh
  QS_IMAGE=quickshell:phase1
  QS_BIN=/tmp/quickshell-build/src/quickshell
  if [ "$QUATTRO" -eq 1 ]; then
    QS_CONTAINER=quickshell-quattro-smoke
    QS_RUNNER=/test/run-quattro-shell.sh
    QS_IMAGE=quickshell:phase1-hypr-lab
    QS_BIN=/tmp/quickshell-services-build/src/quickshell
    "$SCRIPT_DIR/quattro-workloads.sh" init
    WORKLOAD_DIR="$SCRIPT_DIR/../artifacts/workloads"
    QS_WORKLOAD_ARGS="--mount type=bind,src=$WORKLOAD_DIR,dst=/tmp/jetson-workloads,readonly"
    JETSON_POWER_MODE=$(timeout 5 nvpmodel -q 2>/dev/null || echo "NVIDIA power mode unavailable")
    PW_SOCKET=/run/user/$HOST_UID/pipewire-0
    [ -S "$PW_SOCKET" ] || { echo "Host PipeWire socket missing: $PW_SOCKET" >&2; exit 1; }
    QS_AUDIO_ARGS="--mount type=bind,src=$PW_SOCKET,dst=/tmp/host-pipewire,readonly -e PIPEWIRE_REMOTE=/tmp/host-pipewire"
    # Same Quickshell audio module as the panel; read-only, no display needed.
    # shellcheck disable=SC2086
    docker run --rm --network none --user "$HOST_UID:$HOST_GID" \
      $QS_AUDIO_ARGS \
      --mount "type=bind,src=$SCRIPT_DIR/../tests/runtime-smoke,dst=/test,readonly" \
      -e HOME=/tmp -e LANG=C.UTF-8 -e XDG_RUNTIME_DIR=/tmp/probe-runtime \
      -e QT_QPA_PLATFORM=offscreen -e QS_BIN="$QS_BIN" \
      --entrypoint sh "$QS_IMAGE" -c \
      'mkdir -m 700 /tmp/probe-runtime; timeout 15 "$QS_BIN" --no-color -p /test/audio-probe.qml' || {
        echo "Quickshell audio probe failed; desktop has not been stopped." >&2
        exit 1
      }
    [ -d /home/looco/omarchy/shell ]
    DBUS_RUNTIME_DIR=/run/user/$HOST_UID
    DBUS_SOCKET=$DBUS_RUNTIME_DIR/bus
    [ -d "$DBUS_RUNTIME_DIR" ] && [ -S "$DBUS_SOCKET" ] || {
      echo "The host user D-Bus runtime is unavailable: $DBUS_RUNTIME_DIR" >&2
      echo "Log in as $HOST_USER once before starting the Quattro test." >&2
      exit 1
    }
    # Test the real bus handshake before stopping GDM. Docker's AppArmor
    # profile blocks Hello on this host; relax it only for this test sidecar.
    QS_BUS_ARGS="--security-opt apparmor=unconfined --mount type=bind,src=$DBUS_SOCKET,dst=/tmp/host-session-bus,readonly -e DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/host-session-bus"
    # shellcheck disable=SC2086
    docker run --rm --network none --user "$HOST_UID:$HOST_GID" \
      $QS_BUS_ARGS --entrypoint gdbus "$QS_IMAGE" call --session \
      --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
      --method org.freedesktop.DBus.GetId >/dev/null || {
        echo "Container session D-Bus handshake failed; desktop has not been stopped." >&2
        exit 1
      }
  else
    [ -r "$SCRIPT_DIR/../tests/runtime-smoke/layer-panel.qml" ]
  fi
  [ -r "$SCRIPT_DIR/../tests/runtime-smoke/${QS_RUNNER##*/}" ]
  if docker container inspect "$QS_CONTAINER" >/dev/null 2>&1; then
    echo "Container $QS_CONTAINER already exists; preserve or remove it before another shell test." >&2
    exit 1
  fi
fi
if docker container inspect hyprland-phase2-drm >/dev/null 2>&1; then
  echo "Container hyprland-phase2-drm already exists. Inspect its logs or remove that exact stopped container first." >&2
  exit 1
fi
SYSTEM_PROXY_PID=
TELEMETRY_PID=
AGENT_STATUS_PID=
ACTION_GATEWAY_PID=
archive_file() {
  source=$1
  target=$2
  [ -f "$source" ] || return 0
  cp -f "$source" "$SESSION_ARCHIVE_DIR/$target"
}
archive_runtime_evidence() {
  [ "$QUATTRO" -eq 1 ] || return 0
  mkdir -p "$SESSION_ARCHIVE_DIR"
  archive_file "$AGENT_STATUS_DIR/status.json" agent-status.json
  archive_file "$TELEMETRY_DIR/telemetry.json" telemetry.json
  archive_file "$ACTION_GATEWAY_DIR/action-status.json" action-status.json
  archive_file "$ACTION_GATEWAY_DIR/mvp-status.json" mvp-status.json
  archive_file "$ACTION_GATEWAY_DIR/gateway.log" action-gateway.log
  archive_file "$ACTION_GATEWAY_DIR/launcher.log" action-launcher.log
  archive_file "$WORKLOAD_DIR/registry.json" workload-registry.json
  if docker container inspect quickshell-quattro-smoke >/dev/null 2>&1; then
    docker logs quickshell-quattro-smoke >"$SESSION_ARCHIVE_DIR/quickshell-quattro-smoke.log" 2>&1 || true
    docker inspect quickshell-quattro-smoke >"$SESSION_ARCHIVE_DIR/quickshell-quattro-smoke.inspect.json" || true
  fi
  if docker container inspect hyprland-phase2-drm >/dev/null 2>&1; then
    docker logs hyprland-phase2-drm >"$SESSION_ARCHIVE_DIR/hyprland-phase2-drm.log" 2>&1 || true
    docker inspect hyprland-phase2-drm >"$SESSION_ARCHIVE_DIR/hyprland-phase2-drm.inspect.json" || true
  fi
}
stop_system_proxy() {
  if [ -n "$SYSTEM_PROXY_PID" ]; then
    kill "$SYSTEM_PROXY_PID" 2>/dev/null || true
    wait "$SYSTEM_PROXY_PID" 2>/dev/null || true
    SYSTEM_PROXY_PID=
  fi
}
stop_telemetry() {
  if [ -n "$TELEMETRY_PID" ]; then
    kill "$TELEMETRY_PID" 2>/dev/null || true
    wait "$TELEMETRY_PID" 2>/dev/null || true
    TELEMETRY_PID=
  fi
}
stop_agent_status() {
  if [ -n "$AGENT_STATUS_PID" ]; then
    kill "$AGENT_STATUS_PID" 2>/dev/null || true
    wait "$AGENT_STATUS_PID" 2>/dev/null || true
    AGENT_STATUS_PID=
  fi
}
stop_action_gateway() {
  if [ -n "$ACTION_GATEWAY_PID" ]; then
    kill "$ACTION_GATEWAY_PID" 2>/dev/null || true
    wait "$ACTION_GATEWAY_PID" 2>/dev/null || true
    ACTION_GATEWAY_PID=
  fi
}
cleanup_preflight() {
  stop_action_gateway
  stop_telemetry
  stop_agent_status
  stop_system_proxy
}
trap cleanup_preflight EXIT
if [ "$QUATTRO" -eq 1 ]; then
  "$SCRIPT_DIR/quattro-mvp.py" finalize --run-id "$RUN_ID" >/dev/null
  chown -R "$HOST_UID:$HOST_GID" "$SESSION_ARCHIVE_DIR"
  command -v xdg-dbus-proxy >/dev/null
  command -v setpriv >/dev/null
  SYSTEM_PROXY_DIR=$(mktemp -d /tmp/jetson-system-bus.XXXXXX)
  chown "$HOST_UID:$HOST_GID" "$SYSTEM_PROXY_DIR"
  setpriv --reuid="$HOST_UID" --regid="$HOST_GID" --init-groups \
    sh "$SCRIPT_DIR/system-bus-readonly.sh" "$SYSTEM_PROXY_DIR/bus" \
    >"$SYSTEM_PROXY_DIR/proxy.log" 2>&1 &
  SYSTEM_PROXY_PID=$!
  for attempt in 1 2 3 4 5; do
    [ ! -S "$SYSTEM_PROXY_DIR/bus" ] || break
    sleep 1
  done
  [ -S "$SYSTEM_PROXY_DIR/bus" ] || { echo "System bus proxy failed: $SYSTEM_PROXY_DIR/proxy.log" >&2; exit 1; }
  QS_SYSTEM_ARGS="--mount type=bind,src=$SYSTEM_PROXY_DIR/bus,dst=/tmp/host-system-bus,readonly -e DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/host-system-bus"
  # shellcheck disable=SC2086
  docker run --rm --network none --security-opt apparmor=unconfined \
    --user "$HOST_UID:$HOST_GID" $QS_SYSTEM_ARGS \
    --mount "type=bind,src=$SCRIPT_DIR/../tests/runtime-smoke,dst=/test,readonly" \
    -e HOME=/tmp -e LANG=C.UTF-8 -e XDG_RUNTIME_DIR=/tmp/probe-runtime \
    -e QT_QPA_PLATFORM=offscreen -e QS_BIN="$QS_BIN" \
    --entrypoint sh "$QS_IMAGE" -c \
    'mkdir -m 700 /tmp/probe-runtime; timeout 15 "$QS_BIN" --no-color -p /test/system-services-probe.qml'
  [ -x "$SCRIPT_DIR/collect-jetson-telemetry.sh" ] || {
    echo "Telemetry collector is missing or not executable: $SCRIPT_DIR/collect-jetson-telemetry.sh" >&2
    exit 1
  }
  TELEMETRY_DIR=$(mktemp -d /tmp/jetson-telemetry.XXXXXX)
  chown "$HOST_UID:$HOST_GID" "$TELEMETRY_DIR"
  setpriv --reuid="$HOST_UID" --regid="$HOST_GID" --init-groups \
    "$SCRIPT_DIR/collect-jetson-telemetry.sh" "$TELEMETRY_DIR/telemetry.json" \
    >"$TELEMETRY_DIR/collector.log" 2>&1 &
  TELEMETRY_PID=$!
  for attempt in 1 2 3 4 5; do
    [ -s "$TELEMETRY_DIR/telemetry.json" ] && break
    sleep 1
  done
  [ -s "$TELEMETRY_DIR/telemetry.json" ] || {
    echo "Telemetry collector failed: $TELEMETRY_DIR/collector.log" >&2
    exit 1
  }
  QS_TELEMETRY_ARGS="--mount type=bind,src=$TELEMETRY_DIR,dst=/tmp/jetson-telemetry,readonly"
  AGENT_STATUS_DIR=$(mktemp -d /tmp/jetson-agent-status.XXXXXX)
  chown "$HOST_UID:$HOST_GID" "$AGENT_STATUS_DIR"
  # sudo leaves HOME pointing at root. Codex local session discovery belongs to
  # the desktop user, so make that identity explicit before dropping privileges.
  setpriv --reuid="$HOST_UID" --regid="$HOST_GID" --init-groups \
    env HOME="/home/$HOST_USER" XDG_STATE_HOME="/home/$HOST_USER/.local/state" PATH="$HOST_AGENT_PATH" \
    "$SCRIPT_DIR/collect-jetson-agent-status.sh" "$AGENT_STATUS_DIR/status.json" \
    >"$AGENT_STATUS_DIR/collector.log" 2>&1 &
  AGENT_STATUS_PID=$!
  for attempt in 1 2 3 4 5; do
    [ -s "$AGENT_STATUS_DIR/status.json" ] && break
    sleep 1
  done
  [ -s "$AGENT_STATUS_DIR/status.json" ] || {
    echo "Agent status bridge failed: $AGENT_STATUS_DIR/collector.log" >&2
    exit 1
  }
  QS_AGENT_STATUS_ARGS="--mount type=bind,src=$AGENT_STATUS_DIR,dst=/tmp/jetson-agent-status,readonly"
  ACTION_GATEWAY_DIR=$(mktemp -d /tmp/jetson-action-gateway.XXXXXX)
  chown "$HOST_UID:$HOST_GID" "$ACTION_GATEWAY_DIR"
  chmod 0700 "$ACTION_GATEWAY_DIR"
  setpriv --reuid="$HOST_UID" --regid="$HOST_GID" --init-groups \
    env HOME="/home/$HOST_USER" XDG_STATE_HOME="/home/$HOST_USER/.local/state" PATH="$HOST_AGENT_PATH" \
    "$SCRIPT_DIR/quattro-action-gateway.sh" "$ACTION_GATEWAY_DIR" "$AGENT_STATUS_DIR/status.json" "$RUN_ID" \
    >"$ACTION_GATEWAY_DIR/launcher.log" 2>&1 &
  ACTION_GATEWAY_PID=$!
  sleep 1
  kill -0 "$ACTION_GATEWAY_PID" 2>/dev/null || {
    echo "Action gateway failed: $ACTION_GATEWAY_DIR/launcher.log" >&2
    exit 1
  }
  # This is intentionally the sole writable host mount in Quattro. The
  # gateway accepts only one fixed, harmless request and exits with the run.
  QS_ACTION_ARGS="--mount type=bind,src=$ACTION_GATEWAY_DIR,dst=/tmp/jetson-actions"
fi
echo "Preflight passed: console=$ACTIVE_TTY, image=hyprland:phase2-runtime, uid=$HOST_UID"
[ "$CHECK_ONLY" -eq 0 ] || exit 0
[ -t 0 ] || { echo "An interactive local console is required." >&2; exit 1; }
if [ "$(fgconsole)" != "$VT_NUMBER" ]; then
  echo "$ACTIVE_TTY is not the foreground console. Switch to it before starting." >&2
  exit 1
fi
if [ "$STOP_GDM" -eq 0 ] && systemctl is-active --quiet gdm3; then
  echo "GDM is active; use --stop-gdm for the coordinated handoff." >&2
  exit 1
fi

RESTORE_GDM=0
PANEL_STARTED=0
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$PANEL_STARTED" -eq 1 ]; then
    docker stop --time 3 "$QS_CONTAINER" >/dev/null 2>&1 || true
    echo "Quickshell logs retained: sudo docker logs $QS_CONTAINER"
  fi
  docker stop --time 5 hyprland-phase2-drm >/dev/null 2>&1 || true
  stop_action_gateway
  stop_telemetry
  stop_agent_status
  stop_system_proxy
  if [ "$QUATTRO" -eq 1 ]; then
    archive_runtime_evidence
    jq -cn --arg runId "$RUN_ID" --arg state restoring-gdm --arg revision "$(git -C "$SCRIPT_DIR/.." rev-parse HEAD 2>/dev/null || echo unavailable)" \
      '{schemaVersion:1,runId:$runId,state:$state,revision:$revision,stateChangedAt:(now|todateiso8601)}' \
      >"$SESSION_ARCHIVE_DIR/session.json.tmp"
    mv "$SESSION_ARCHIVE_DIR/session.json.tmp" "$SESSION_ARCHIVE_DIR/session.json"
    cp -f "$SCRIPT_DIR/../mvp/acceptance.json" "$SESSION_ARCHIVE_DIR/acceptance-manifest.json"
  fi
  if [ "$RESTORE_GDM" -eq 1 ]; then
    systemctl start gdm3 || true
  fi
  if [ "$QUATTRO" -eq 1 ]; then
    final_state=awaiting-visual-check
    [ "$result" -eq 0 ] || final_state=failed
    jq -cn --arg runId "$RUN_ID" --arg state "$final_state" --arg revision "$(git -C "$SCRIPT_DIR/.." rev-parse HEAD 2>/dev/null || echo unavailable)" --argjson exitCode "$result" \
      '{schemaVersion:1,runId:$runId,state:$state,revision:$revision,exitCode:$exitCode,stateChangedAt:(now|todateiso8601)}' \
      >"$SESSION_ARCHIVE_DIR/session.json.tmp"
    mv "$SESSION_ARCHIVE_DIR/session.json.tmp" "$SESSION_ARCHIVE_DIR/session.json"
    chown -R "$HOST_UID:$HOST_GID" "$SESSION_ARCHIVE_DIR"
  fi
  echo "Test ended (status $result). Container logs retained: sudo docker logs hyprland-phase2-drm"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

# Stopping GDM can blank the active screen or switch VTs. Doing it here means
# this already-running process continues directly into the DRM compositor.
if [ "$STOP_GDM" -eq 1 ]; then
  # GDM's service can finish stopping while its separate logind session scope
  # is still tearing down Xorg, which can subsequently switch away from our VT.
  GRAPHICAL_SCOPES=
  for session in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    seat=$(loginctl show-session "$session" -p Seat --value 2>/dev/null || true)
    type=$(loginctl show-session "$session" -p Type --value 2>/dev/null || true)
    state=$(loginctl show-session "$session" -p State --value 2>/dev/null || true)
    if [ "$seat" = seat0 ] && [ "$state" != closing ]; then
      case "$type" in
        x11|wayland)
          scope=$(loginctl show-session "$session" -p Scope --value)
          GRAPHICAL_SCOPES="$GRAPHICAL_SCOPES $scope" ;;
      esac
    fi
  done
  if systemctl is-active --quiet gdm3; then RESTORE_GDM=1; fi
  systemctl stop gdm3
  echo "Waiting for the previous graphical session to finish shutting down..."
  remaining=60
  while :; do
    pending=
    for scope in $GRAPHICAL_SCOPES; do
      state=$(systemctl show "$scope" -p ActiveState --value)
      case "$state" in
        active|activating|deactivating) pending="$pending $scope" ;;
      esac
    done
    [ -n "$pending" ] || break
    if [ "$remaining" -eq 0 ]; then
      echo "Graphical sessions still shutting down:$pending. Aborting and restoring GDM." >&2
      exit 1
    fi
    sleep 1
    remaining=$((remaining - 1))
  done
fi
# GDM shutdown can change the foreground VT. seatd uses the active VT, so
# explicitly reactivate the SAME console whose device is passed to Docker.
chvt "$VT_NUMBER"
[ "$(fgconsole)" = "$VT_NUMBER" ] || { echo "Failed to activate $ACTIVE_TTY" >&2; exit 1; }

set --
if [ "$PANEL" -eq 1 ] || [ "$QUATTRO" -eq 1 ]; then
  # An isolated volume shares only this test's runtime directory, not the host's.
  RUNTIME_VOLUME="jetson-wayland-$(date +%Y%m%d-%H%M%S)-$$"
  docker volume create "$RUNTIME_VOLUME" >/dev/null
  echo "Shared runtime volume retained for diagnostics: $RUNTIME_VOLUME"
  PANEL_STARTED=1
  QS_ARGS="--mount type=bind,src=$SCRIPT_DIR/../tests/runtime-smoke,dst=/test,readonly"
  if [ "$QUATTRO" -eq 1 ]; then
    QS_ARGS="$QS_ARGS --mount type=bind,src=/home/looco/omarchy,dst=/omarchy,readonly"
    QS_ARGS="$QS_ARGS $QS_BUS_ARGS $QS_AUDIO_ARGS $QS_SYSTEM_ARGS $QS_TELEMETRY_ARGS $QS_AGENT_STATUS_ARGS $QS_WORKLOAD_ARGS $QS_ACTION_ARGS"
    QS_ARGS="$QS_ARGS -e OMARCHY_PATH=/omarchy -e QML_IMPORT_PATH=/omarchy/shell"
  fi
  # shellcheck disable=SC2086
  docker run -d --name "$QS_CONTAINER" \
    --label "dev.omarchy-quattro.run-id=$RUN_ID" \
    --network none --runtime=nvidia --gpus all --device=/dev/dri \
    --user "$HOST_UID:$HOST_GID" \
    --group-add "$VIDEO_GID" --group-add "$RENDER_GID" \
    --mount "type=volume,src=$RUNTIME_VOLUME,dst=/tmp/hypr-runtime" \
    $QS_ARGS \
    -e HOME=/tmp -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
    -e QS_BIN="$QS_BIN" \
    -e JETSON_POWER_MODE="${JETSON_POWER_MODE:-}" \
    --mount type=bind,src=/etc/localtime,dst=/etc/localtime,readonly \
    -e LANG=C.UTF-8 \
    -e QT_QPA_PLATFORM=wayland \
    --entrypoint sh "$QS_IMAGE" "$QS_RUNNER"
  set -- --mount "type=volume,src=$RUNTIME_VOLUME,dst=/tmp/hypr-runtime"
fi

docker run -it \
  "$@" \
  --name hyprland-phase2-drm \
  --label "dev.omarchy-quattro.run-id=$RUN_ID" \
  --network none \
  --runtime=nvidia \
  --gpus all \
  --device=/dev/dri \
  --device=/dev/input \
  --device-cgroup-rule='c 13:* rwm' \
  --mount type=bind,src=/run/udev,dst=/run/udev,readonly \
  --mount "type=bind,src=$TEST_CONFIG,dst=/etc/hyprland-smoke.conf,readonly" \
  --device=/dev/tty0 \
  --device="$ACTIVE_TTY" \
  --cap-add=SYS_TTY_CONFIG \
  -e HYPRLAND_UID="$HOST_UID" \
  -e HYPRLAND_GID="$HOST_GID" \
  -e HYPRLAND_INPUT_GID="$INPUT_GID" \
  -e HYPRLAND_VIDEO_GID="$VIDEO_GID" \
  -e HYPRLAND_RENDER_GID="$RENDER_GID" \
  -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
  hyprland:phase2-runtime --config /etc/hyprland-smoke.conf
