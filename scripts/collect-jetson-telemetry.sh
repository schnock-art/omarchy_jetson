#!/bin/sh
# Read-only host telemetry collector for the Quattro lab sidecar.
set -eu

[ "$#" -eq 1 ] || { echo "Usage: $0 OUTPUT_JSON" >&2; exit 2; }
OUT_FILE=$1
OUT_DIR=$(dirname "$OUT_FILE")
FIFO="$OUT_DIR/tegrastats.fifo"
rm -f "$FIFO"
mkfifo "$FIFO"

tegrastats --interval 1000 >"$FIFO" 2>/dev/null &
TEGRAPID=$!
cleanup() {
  kill "$TEGRAPID" 2>/dev/null || true
  wait "$TEGRAPID" 2>/dev/null || true
  rm -f "$FIFO"
}
trap cleanup EXIT HUP INT TERM

while IFS= read -r line; do
  ram=$(printf '%s\n' "$line" | sed -n 's/.*RAM \([0-9]*\)\/\([0-9]*\)MB.*/\1 \2/p')
  gpu=$(printf '%s\n' "$line" | sed -n 's/.*GR3D_FREQ \([0-9]*\)%.*/\1/p')
  cpu=$(printf '%s\n' "$line" | sed -n 's/.*CPU \[\([^]]*\)\].*/\1/p' | awk -F',' '
    {
      for (i = 1; i <= NF; i++) {
        token = $i
        sub(/^[[:space:]]*/, "", token)
        sub(/%@.*/, "", token)
        if (token ~ /^[0-9]+$/) { sum += token; count++ }
      }
    }
    END { if (count) printf "%d", sum / count; else printf "0" }')
  tj=$(printf '%s\n' "$line" | sed -n 's/.*tj@\([0-9.]*\)C.*/\1/p')
  gpu_temp=$(printf '%s\n' "$line" | sed -n 's/.*gpu@\([0-9.]*\)C.*/\1/p')
  vin=$(printf '%s\n' "$line" | sed -n 's/.*VIN_SYS_5V0 \([0-9]*\)mW.*/\1/p')
  mode=$(nvpmodel -q 2>/dev/null | sed -n '1p' | sed 's/["\\]/ /g')
  ram_used=0
  ram_total=0
  if [ -n "$ram" ]; then
    ram_used=${ram%% *}
    ram_total=${ram#* }
  fi
  tmp="$OUT_FILE.tmp"
  updated=$(date --iso-8601=seconds)
  jq -cn --arg updated "$updated" --arg mode "$mode" \
    --argjson ram_used "$ram_used" --argjson ram_total "$ram_total" \
    --argjson cpu "${cpu:-0}" --argjson gpu "${gpu:-0}" \
    --argjson junction "${tj:-0}" --argjson gpu_temp "${gpu_temp:-0}" \
    --argjson vin "${vin:-0}" \
    '{updatedAt:$updated,ramUsedMb:$ram_used,ramTotalMb:$ram_total,cpuPercent:$cpu,gpuPercent:$gpu,junctionC:$junction,gpuC:$gpu_temp,vinMilliwatts:$vin,powerMode:$mode}' >"$tmp"
  mv "$tmp" "$OUT_FILE"
done <"$FIFO"
