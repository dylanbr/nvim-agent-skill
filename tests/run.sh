#!/usr/bin/env bash
# Tests for nv against a headless Neovim that this script starts and stops.
# It never touches your own editor: every call passes the test server's socket.
#
# Usage: tests/run.sh [NAME...]   run all of tests/integration/*.sh, or the named
#                                 ones (e.g. tests/run.sh prompts)
# Needs nvim, perl, lsof, python3. The full run takes about 10-15s, mostly
# waiting for file timestamps to change.

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

TOP=$(mktemp -d "${TMPDIR:-/tmp}/nvtest.XXXXXX")
TOP=$(cd "$TOP" && pwd -P)
trap 'stop_all >/dev/null; rm -rf "$TOP"' EXIT

files=()
if [ $# -eq 0 ]; then
  files=("$ROOT"/tests/integration/*.sh)
else
  for n in "$@"; do
    f="$ROOT/tests/integration/${n%.sh}.sh"
    [ -f "$f" ] || { echo "no test file: $f"; exit 1; }
    files+=("$f")
  done
fi

start_server
first=1
for f in "${files[@]}"; do
  CURRENT=$(basename "$f" .sh)
  echo "$CURRENT"
  [ $first -eq 1 ] || reset_server
  first=0
  DIR="$TOP/$CURRENT"
  mkdir -p "$DIR"
  . "$f"
done
stop_all
trap 'rm -rf "$TOP"' EXIT

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || { printf 'failed:\n%s' "$FAILED"; exit 1; }
