#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TRIGGER="$ROOT_DIR/scripts/quattro-s5-termination-trigger.sh"
fail() { echo "S5 termination-trigger fixture failed: $*" >&2; exit 1; }

sh -n "$TRIGGER"
grep -Fq 'TRIGGER=/run/omarchy-quattro/s5-termination-once.json' "$TRIGGER" || fail 'trigger path changed'
grep -Fq 'install -d -m 0755 -o root -g root /run/omarchy-quattro' "$TRIGGER" || fail 'socket directory is not traversable by its group'
grep -Fq 'failure:"terminate-after-ready-v1"' "$TRIGGER" || fail 'termination mode is not fixed'
grep -Fq 'chmod 0600 "$tmp"' "$TRIGGER" || fail 'trigger file is not root-only'
if grep -Eq 'rm -rf|eval' "$TRIGGER"; then fail 'unsafe trigger operation present'; fi
echo 'S5 termination-trigger fixture checks passed'
