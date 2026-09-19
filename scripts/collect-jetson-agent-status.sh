#!/bin/sh
# Read-only host-side agent readiness collector for the Quattro lab.
set -eu

[ "$#" -eq 1 ] || { echo "Usage: $0 OUTPUT_JSON" >&2; exit 2; }
OUT_FILE=$1
OUT_DIR=$(dirname "$OUT_FILE")
mkdir -p "$OUT_DIR"
usage_dir=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage
omarchy_bin=${OMARCHY_PATH:-/home/looco/omarchy}/bin

while :; do
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
  sleep 60
done
