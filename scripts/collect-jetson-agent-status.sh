#!/bin/sh
# Read-only host-side agent readiness collector for the Quattro lab.
set -eu

[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || { echo "Usage: $0 [--once] OUTPUT_JSON" >&2; exit 2; }
ONCE=0
if [ "${1:-}" = --once ]; then
  ONCE=1
  shift
fi
OUT_FILE=$1
OUT_DIR=$(dirname "$OUT_FILE")
mkdir -p "$OUT_DIR"
usage_dir=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage
omarchy_bin=${OMARCHY_PATH:-/home/looco/omarchy}/bin
# Codex Desktop bundles its CLI outside the login-shell PATH on this Jetson.
# Keep discovery host-side; only the sanitized collector result enters Docker.
if ! command -v codex >/dev/null 2>&1 && [ -x /usr/lib/chatgpt/resources/codex ]; then
  PATH="/usr/lib/chatgpt/resources:$PATH"
  export PATH
fi

collect() {
  records=0
  [ -d "$usage_dir" ] && records=$(find "$usage_dir" -maxdepth 1 -type f -name '*.json' | wc -l)
  collectors=0
  [ -d "$omarchy_bin" ] && collectors=$(find "$omarchy_bin" -maxdepth 1 -type f -name 'omarchy-agent-usage-*' ! -name '*-update' | wc -l)
  updater=0
  [ -x "$omarchy_bin/omarchy-agent-usage-update" ] && updater=1
  codex='{}'
  codex_collector="$omarchy_bin/omarchy-agent-usage-codex"
  if [ -x "$codex_collector" ]; then
    codex=$(
      timeout 45 "$codex_collector" --force 2>/dev/null || printf '{}'
    )
    jq -e . >/dev/null 2>&1 <<EOF || codex='{}'
$codex
EOF
  fi
  tmp="$OUT_FILE.tmp"
  jq -cn --argjson codex "$codex" \
    '{bridge:"ready",usageRecords:(if ($codex.id // "") != "" then 1 else 0 end),collectors:'"$collectors"',updaterPresent:'"$updater"',providerLaunch:"deferred",codex:$codex}' >"$tmp"
  mv "$tmp" "$OUT_FILE"
}

while :; do
  collect
  [ "$ONCE" -eq 0 ] || exit 0
  sleep 60
done
