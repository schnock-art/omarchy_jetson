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
  tmp="$OUT_FILE.tmp"
  printf '{"bridge":"ready","usageRecords":%s,"collectors":%s,"updaterPresent":%s,"providerLaunch":"deferred"}\n' \
    "$records" "$collectors" "$updater" >"$tmp"
  mv "$tmp" "$OUT_FILE"
  sleep 5
done
