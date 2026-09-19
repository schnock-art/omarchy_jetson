#!/bin/sh
# Capture or verify read-only prerequisites for the Quattro reboot check.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BASELINE_DIR="$ROOT_DIR/artifacts/reboot-baselines"

usage() {
  echo "Usage: $0 --capture | --verify BASELINE_JSON" >&2
  exit 2
}

docker_cmd() {
  if [ "$(id -u)" -eq 0 ]; then docker "$@"; else sudo -n docker "$@"; fi
}

image_id() { docker_cmd image inspect -f '{{.Id}}' "$1" 2>/dev/null || true; }
service_state() { systemctl is-active "$1" 2>/dev/null || true; }
socket_state() { [ -S "$1" ] && printf present || printf absent; }

capture() {
  mkdir -p "$BASELINE_DIR"
  stamp=$(date +%Y%m%d-%H%M%S)
  output="$BASELINE_DIR/$stamp.json"
  jq -n \
    --arg revision "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
    --arg kernel "$(uname -r)" \
    --arg gdm "$(service_state gdm3)" \
    --arg docker "$(service_state docker)" \
    --arg bus "$(socket_state /run/user/2002/bus)" \
    --arg pipewire "$(socket_state /run/user/2002/pipewire-0)" \
    --arg hyprland "$(image_id hyprland:phase2-runtime)" \
    --arg quickshell "$(image_id quickshell:phase1-hypr-lab)" \
    '{revision:$revision,kernel:$kernel,gdm:$gdm,docker:$docker,userBus:$bus,pipewire:$pipewire,hyprlandImage:$hyprland,quickshellImage:$quickshell}' \
    >"$output"
  echo "Captured reboot baseline: $output"
  jq . "$output"
}

verify() {
  baseline=$1
  [ -r "$baseline" ] || { echo "Baseline is unreadable: $baseline" >&2; exit 2; }
  jq empty "$baseline"
  current=$(mktemp /tmp/quattro-reboot-current.XXXXXX)
  current_result=$(mktemp /tmp/quattro-reboot-result.XXXXXX)
  trap 'rm -f "$current" "$current_result"' EXIT
  jq -n \
    --arg kernel "$(uname -r)" \
    --arg gdm "$(service_state gdm3)" \
    --arg docker "$(service_state docker)" \
    --arg bus "$(socket_state /run/user/2002/bus)" \
    --arg pipewire "$(socket_state /run/user/2002/pipewire-0)" \
    --arg hyprland "$(image_id hyprland:phase2-runtime)" \
    --arg quickshell "$(image_id quickshell:phase1-hypr-lab)" \
    '{kernel:$kernel,gdm:$gdm,docker:$docker,userBus:$bus,pipewire:$pipewire,hyprlandImage:$hyprland,quickshellImage:$quickshell}' >"$current"
  jq -n --slurpfile before "$baseline" --slurpfile after "$current" '
    ($before[0]) as $b | ($after[0]) as $a |
    {gdm: ($a.gdm == "active"), docker: ($a.docker == "active"), userBus: ($a.userBus == "present"), pipewire: ($a.pipewire == "present"), images: ($a.hyprlandImage == $b.hyprlandImage and $a.quickshellImage == $b.quickshellImage), kernel: ($a.kernel == $b.kernel)}' \
    >"$current_result"
  jq . "$current_result"
  jq -e '.gdm and .docker and .userBus and .pipewire and .images and .kernel' "$current_result" >/dev/null || exit 1
  echo "PASS  Reboot prerequisites match the baseline"
}

[ "$#" -ge 1 ] || usage
case "$1" in
  --capture) [ "$#" -eq 1 ] || usage; capture ;;
  --verify) [ "$#" -eq 2 ] || usage; verify "$2" ;;
  *) usage ;;
esac
