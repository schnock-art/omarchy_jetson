#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RUNTIME="$ROOT_DIR/scripts/quattro-gdm-session-runtime.sh"

fail() {
  echo "GDM session runtime fixture failed: $*" >&2
  exit 1
}

if "$RUNTIME" unknown run-1 17 2002 2002 tty2 >/dev/null 2>&1; then
  fail 'unknown operation was accepted'
fi
if "$RUNTIME" supervise '../escape' 17 2002 2002 tty2 >/dev/null 2>&1; then
  fail 'unsafe run ID was accepted'
fi
if "$RUNTIME" supervise run-1 17 2002 2002 /dev/tty2 >/dev/null 2>&1; then
  fail 'unsafe TTY value was accepted'
fi
if grep -Eq '(^|[[:space:]])eval([[:space:]]|$)' "$RUNTIME"; then
  fail 'runtime contains eval'
fi
grep -Fq 'HYPR_IMAGE=hyprland:phase2-runtime' "$RUNTIME" || fail 'fixed Hyprland image missing'
grep -Fq 'QS_IMAGE=quickshell:phase1-hypr-lab' "$RUNTIME" || fail 'fixed Quickshell image missing'
grep -Fq -- '--network none' "$RUNTIME" || fail 'network isolation missing'
grep -Fq 'src=$OMARCHY_ROOT,dst=/omarchy,readonly' "$RUNTIME" || fail 'read-only Omarchy mount missing'
grep -Fq 'quickshell-quattro-smoke.log' "$RUNTIME" || fail 'canonical Quickshell archive missing'
grep -Fq 'hyprland-phase2-drm.log' "$RUNTIME" || fail 'canonical Hyprland archive missing'
grep -Fq -- '-e QUATTRO_SEATD_UNBOUND=1' "$RUNTIME" || fail 'GDM-owned VT mode missing'

ENTRYPOINT="$ROOT_DIR/containers/hyprland-runtime/hyprland-seatd-entrypoint"
grep -Fq 'SEATD_VTBOUND=0' "$ENTRYPOINT" || fail 'unbound seatd mode missing'
grep -Fq 'seatd -u hyprland -g input -l info' "$ENTRYPOINT" || fail 'direct seatd startup missing'
grep -Fq 'exec seatd-launch --' "$ENTRYPOINT" || fail 'lab VT-bound startup missing'

echo 'GDM session fixed-runtime fixture checks passed'
