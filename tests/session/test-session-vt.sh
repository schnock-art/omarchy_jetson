#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$ROOT_DIR/scripts/quattro-session-common.sh"
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
# Model a GDM foreground change without opening any host device.
cat() {
  attempt=$(command cat "$fixture_dir/count")
  attempt=$((attempt + 1))
  printf '%s\n' "$attempt" >"$fixture_dir/count"
  case "$scenario" in
    delayed) [ "$attempt" -lt 3 ] && echo tty1 || echo tty2 ;;
    wrong) echo tty1 ;;
    unavailable) return 1 ;;
    *) echo tty2 ;;
  esac
}
timeout() {
  case "$scenario" in
    malformed) echo 'User=garbage'; return ;;
    vanished) return 1 ;;
  esac
  printf '%s\n' User=2002 Active=yes Remote=no Seat=seat0 Type=wayland TTY=tty2
}
sleep() { :; }
for scenario in ready delayed wrong unavailable malformed vanished; do
  printf '0\n' >"$fixture_dir/count"
  if quattro_wait_for_session_vt 17 2002 tty2 "$fixture_dir/$scenario.jsonl"; then
    case "$scenario" in ready|delayed) ;; *) exit 1 ;; esac
  else
    case "$scenario" in ready|delayed) exit 1 ;; esac
  fi
  jq -se 'all(.[]; .schemaVersion == 1)' "$fixture_dir/$scenario.jsonl" >/dev/null
done
[ "$(wc -l <"$fixture_dir/ready.jsonl")" -eq 3 ]
[ "$(wc -l <"$fixture_dir/delayed.jsonl")" -eq 5 ]
[ "$(wc -l <"$fixture_dir/wrong.jsonl")" -eq 10 ]
# A fresh invocation must not reuse the previous invocation's readiness.
scenario=wrong
if quattro_wait_for_session_vt 18 2002 tty2 "$fixture_dir/repeat.jsonl"; then exit 1; fi
echo 'Session foreground VT fixtures passed'
