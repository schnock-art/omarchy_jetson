#!/bin/sh
set -eu
exec python3 - "$1" <<'PY'
import signal
import socket
import sys

server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1])
server.listen(1)
signal.pause()
PY
