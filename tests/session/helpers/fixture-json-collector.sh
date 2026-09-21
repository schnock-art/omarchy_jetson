#!/bin/sh
set -eu
output=$1
if [ "${QUATTRO_FIXTURE_COLLECTOR_FAIL:-0}" -eq 0 ]; then
  printf '%s\n' '{"fixture":true}' >"$output.tmp"
  mv "$output.tmp" "$output"
fi
trap 'exit 0' HUP INT TERM
while :; do sleep 1; done
