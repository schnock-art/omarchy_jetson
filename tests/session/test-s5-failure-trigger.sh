#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TRIGGER="$ROOT_DIR/scripts/quattro-s5-failure-trigger.sh"

fail() { echo "S5 failure-trigger fixture failed: $*" >&2; exit 1; }

sh -n "$TRIGGER"
grep -Fq 'TRIGGER=/run/omarchy-quattro/s5-failure-once.json' "$TRIGGER" || fail 'trigger path changed'
grep -Fq 'install -d -m 0755 -o root -g root /run/omarchy-quattro' "$TRIGGER" || fail 'socket directory is not traversable by its group'
grep -Fq 'failure:"preflight-v1"' "$TRIGGER" || fail 'failure mode is not fixed'
grep -Fq 'chmod 0600 "$tmp"' "$TRIGGER" || fail 'trigger file is not root-only'
if grep -Eq 'rm -rf|eval' "$TRIGGER"; then fail 'unsafe trigger operation present'; fi

echo 'S5 failure-trigger fixture checks passed'
