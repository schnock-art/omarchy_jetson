#!/bin/sh
set -eu
request_dir=$1
printf '%s\n' '{"schemaVersion":1,"state":"ready"}' >"$request_dir/action-status.json"
printf '%s\n' '{"schemaVersion":1,"state":"ready"}' >"$request_dir/mvp-status.json"
printf '%s\n' 'fixture gateway ready' >"$request_dir/gateway.log"
trap 'exit 0' HUP INT TERM
while :; do sleep 1; done
