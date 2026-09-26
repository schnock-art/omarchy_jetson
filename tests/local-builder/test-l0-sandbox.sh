#!/bin/sh
# Prove only the fixed L0 Bubblewrap/systemd isolation primitive; this is not a runner.
set -eu

command -v bwrap >/dev/null 2>&1 || { echo 'L0 sandbox fixture: bwrap unavailable' >&2; exit 1; }
command -v systemd-run >/dev/null 2>&1 || { echo 'L0 sandbox fixture: systemd-run unavailable' >&2; exit 1; }

test_root=$(mktemp -d /tmp/quattro-local-builder-l0.XXXXXX)
cleanup() {
  case "$test_root" in
    /tmp/quattro-local-builder-l0.*) rm -rf -- "$test_root" ;;
    *) echo "Refusing unsafe fixture cleanup: $test_root" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_root/worktree" "$test_root/evidence" "$test_root/outside"
printf '%s\n' original >"$test_root/worktree/editable.txt"
printf '%s\n' retained >"$test_root/outside/sentinel"
ln -s "$test_root/outside/sentinel" "$test_root/worktree/escape-link"
host_net_ns=$(readlink /proc/self/ns/net)
host_pid_ns=$(readlink /proc/self/ns/pid)

# Prove the installed Git can create an independent linked worktree without
# touching this repository's worktree metadata.
mkdir -p "$test_root/git-source"
git -C "$test_root/git-source" init --quiet
git -C "$test_root/git-source" config user.name fixture
git -C "$test_root/git-source" config user.email fixture@invalid
printf '%s\n' base >"$test_root/git-source/tracked.txt"
git -C "$test_root/git-source" add tracked.txt
git -C "$test_root/git-source" commit --quiet -m base
git -C "$test_root/git-source" worktree add --quiet --detach "$test_root/git-worktree" HEAD
printf '%s\n' changed >"$test_root/git-worktree/tracked.txt"
[ "$(cat "$test_root/git-source/tracked.txt")" = base ]
[ -n "$(git -C "$test_root/git-worktree" status --porcelain=v1)" ]

bwrap --unshare-all --unshare-user --disable-userns --assert-userns-disabled \
  --die-with-parent --new-session --cap-drop ALL --clearenv \
  --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib \
  --dir /etc --ro-bind /etc/ld.so.cache /etc/ld.so.cache \
  --proc /proc --dev /dev --tmpfs /tmp --tmpfs /run \
  --dir /workspace --dir /evidence \
  --bind "$test_root/worktree" /workspace \
  --bind "$test_root/evidence" /evidence \
  --setenv HOME /tmp/home --setenv PATH /usr/bin:/bin --setenv LANG C.UTF-8 \
  --setenv HOST_NET_NS "$host_net_ns" --setenv HOST_PID_NS "$host_pid_ns" \
  --setenv GIT_CONFIG_NOSYSTEM 1 --setenv GIT_CONFIG_GLOBAL /dev/null \
  --chdir /workspace /bin/sh -c '
set -eu
fail() { echo "L0 sandbox assertion failed: $1" >&2; exit "$2"; }
mkdir -p "$HOME"
printf "%s\n" changed >editable.txt
printf "%s\n" proof >/evidence/proof.txt

[ "$(readlink /proc/self/ns/net)" != "$HOST_NET_NS" ] || fail network-namespace 21
[ "$(readlink /proc/self/ns/pid)" != "$HOST_PID_NS" ] || fail pid-namespace 22
python3 - <<"PY"
status = {}
with open("/proc/self/status", encoding="utf-8") as source:
    for line in source:
        if ":" in line:
            key, value = line.split(":", 1)
            status[key] = value.strip()
assert status["CapEff"] == "0000000000000000"
assert status["CapBnd"] == "0000000000000000"
assert status["NoNewPrivs"] == "1"
PY
[ ! -e /run/docker.sock ] || fail docker-socket-visible 26
[ ! -e /home/looco/repos/omarchy_jetson ] || fail primary-checkout-visible 27
[ "$(find /proc/[0-9]* -maxdepth 0 2>/dev/null | wc -l)" -le 8 ] || fail host-processes-visible 28

if cat escape-link >/dev/null 2>&1; then fail symlink-read-escape 29; fi
if (printf x >escape-link) 2>/dev/null; then fail symlink-write-escape 30; fi
if sudo -n true >/dev/null 2>&1; then fail sudo-succeeded 31; fi
if unshare --user true >/dev/null 2>&1; then fail nested-userns-succeeded 32; fi

python3 - <<"PY"
import socket
for family, address in ((socket.AF_INET, ("127.0.0.1", 9)), (socket.AF_INET6, ("::1", 9))):
    connection = socket.socket(family, socket.SOCK_STREAM)
    connection.settimeout(0.2)
    try:
        connection.connect(address)
    except OSError:
        pass
    else:
        raise SystemExit("sandbox network namespace unexpectedly connected")
    finally:
        connection.close()
PY
'

[ "$(cat "$test_root/worktree/editable.txt")" = changed ]
[ "$(cat "$test_root/evidence/proof.txt")" = proof ]
[ "$(cat "$test_root/outside/sentinel")" = retained ]

# A transient user service supplies the future runner's cgroup-wide time bound.
unit="quattro-l0-fixture-$$"
systemd-run --user --unit "$unit" --wait --collect --quiet \
  -p RuntimeMaxSec=1 -p KillMode=control-group -p TasksMax=8 \
  -p MemoryMax=128M -p NoNewPrivileges=yes \
  /bin/sh -c 'sleep 30 & wait' >/dev/null 2>&1 && {
    echo 'L0 sandbox fixture: bounded unit unexpectedly succeeded' >&2
    exit 1
  }
systemctl --user is-active --quiet "$unit" && {
  echo 'L0 sandbox fixture: bounded unit remained active' >&2
  exit 1
}

echo 'Local-builder L0 sandbox fixture passed'
