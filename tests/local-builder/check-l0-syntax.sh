#!/bin/sh
# Keep the L0 design gate independent of the accepted display preflight.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

python3 - "$ROOT_DIR/scripts/local-builder-l0-inventory.py" <<'PY'
import ast
import pathlib
import sys
ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])
PY
sh -n "$ROOT_DIR/tests/local-builder/test-l0-sandbox.sh"
sh -n "$ROOT_DIR/tests/local-builder/test-l0-operator-context.sh"
command -v apparmor_parser >/dev/null 2>&1 || {
  echo 'L0 syntax check: apparmor_parser unavailable' >&2
  exit 1
}
apparmor_parser -Q -T "$ROOT_DIR/local-builder/apparmor/omarchy-quattro-local-builder-controller"

echo 'Local-builder L0 syntax validation passed'
