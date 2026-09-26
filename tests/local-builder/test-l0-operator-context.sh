#!/bin/sh
# Gate the Bubblewrap primitive from the normal user-manager AppArmor context.
set -eu

command -v bwrap >/dev/null 2>&1 || { echo 'L0 operator-context fixture: bwrap unavailable' >&2; exit 1; }
command -v systemd-run >/dev/null 2>&1 || { echo 'L0 operator-context fixture: systemd-run unavailable' >&2; exit 1; }

unit="quattro-l0-operator-context-$$"
systemd-run --user --unit "$unit" --wait --collect --pipe \
  /bin/sh -c '
    printf "apparmor-context="
    cat /proc/self/attr/current
    exec bwrap --unshare-all --unshare-user --disable-userns \
      --assert-userns-disabled --die-with-parent --new-session --cap-drop ALL \
      --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib \
      --dir /etc --ro-bind /etc/ld.so.cache /etc/ld.so.cache \
      --proc /proc --dev /dev /bin/true
  '

echo 'Local-builder L0 normal operator-context fixture passed'
