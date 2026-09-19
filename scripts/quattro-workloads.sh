#!/bin/sh
# Explicit, narrow workload registry for the Jetson Quattro lab.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
WORKLOAD_DIR="$ROOT_DIR/artifacts/workloads"
REGISTRY="$WORKLOAD_DIR/registry.json"

usage() {
  echo "Usage: $0 <init|list|sample|finish ID EXIT_CODE>" >&2
  exit 2
}

init() {
  mkdir -p "$WORKLOAD_DIR"
  [ -f "$REGISTRY" ] || printf '{"updatedAt":"","jobs":[]}\n' >"$REGISTRY"
}

write_update() {
  tmp="$REGISTRY.tmp"
  jq "$@" "$REGISTRY" >"$tmp"
  mv "$tmp" "$REGISTRY"
}

finish() {
  id=$1
  exit_code=$2
  init
  now=$(date --iso-8601=seconds)
  state=completed
  [ "$exit_code" -eq 0 ] || state=failed
  write_update --arg id "$id" --arg now "$now" --arg state "$state" --argjson code "$exit_code" \
    '.updatedAt=$now | .jobs |= map(if .id == $id then . + {state:$state,finishedAt:$now,exitCode:$code} else . end)'
}

sample() {
  init
  id="sample-$(date +%Y%m%d-%H%M%S)"
  now=$(date --iso-8601=seconds)
  log="$WORKLOAD_DIR/$id.log"
  printf 'Sample workload %s started at %s\n' "$id" "$now" >"$log"
  write_update --arg id "$id" --arg now "$now" --arg log "artifacts/workloads/$id.log" \
    '.updatedAt=$now | .jobs=[{id:$id,name:"Harmless sample",state:"running",owner:"lab",startedAt:$now,logPath:$log}] + .jobs'
  (
    sleep 15
    printf 'Sample workload %s completed at %s\n' "$id" "$(date --iso-8601=seconds)" >>"$log"
    "$0" finish "$id" 0
  ) &
  echo "Started harmless sample workload: $id"
}

[ "$#" -ge 1 ] || usage
case "$1" in
  init) [ "$#" -eq 1 ] || usage; init ;;
  list) [ "$#" -eq 1 ] || usage; init; jq . "$REGISTRY" ;;
  sample) [ "$#" -eq 1 ] || usage; sample ;;
  finish) [ "$#" -eq 3 ] || usage; finish "$2" "$3" ;;
  *) usage ;;
esac
