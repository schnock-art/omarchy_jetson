#!/bin/sh
# Root-only, one-shot S5-3 post-ready compositor termination injection.
set -eu

TRIGGER=/run/omarchy-quattro/s5-termination-once.json
usage() { echo "Usage: $0 {status|arm --approve|clear --approve}" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
operation=$1
approve=${2:-}
case "$operation" in
  status)
    [ "$#" -eq 1 ] || usage
    if [ -e "$TRIGGER" ]; then [ -f "$TRIGGER" ] && [ ! -L "$TRIGGER" ] || { echo 'unsafe trigger' >&2; exit 1; }; jq . "$TRIGGER"; else jq -n '{armed:false}'; fi
    ;;
  arm)
    [ "$approve" = --approve ] && [ "$#" -eq 2 ] || usage
    [ "$(id -u)" -eq 0 ] || { echo 'arm must run as root' >&2; exit 1; }
    [ ! -e "$TRIGGER" ] || { echo 'S5 termination trigger is already armed' >&2; exit 1; }
    install -d -m 0755 -o root -g root /run/omarchy-quattro
    tmp="$TRIGGER.tmp.$$"; umask 077
    jq -cn '{schemaVersion:1,failure:"terminate-after-ready-v1",armedAt:(now|todateiso8601)}' >"$tmp"
    chown root:root "$tmp"; chmod 0600 "$tmp"; mv "$tmp" "$TRIGGER"
    echo 'Armed one-shot S5 post-ready termination.'
    ;;
  clear)
    [ "$approve" = --approve ] && [ "$#" -eq 2 ] || usage
    [ "$(id -u)" -eq 0 ] || { echo 'clear must run as root' >&2; exit 1; }
    [ -e "$TRIGGER" ] || exit 0
    [ -f "$TRIGGER" ] && [ ! -L "$TRIGGER" ] || { echo 'unsafe trigger' >&2; exit 1; }
    rm -- "$TRIGGER"; echo 'Cleared unconsumed S5 termination trigger.'
    ;;
  *) usage ;;
esac
