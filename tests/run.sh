#!/usr/bin/env bash
# Tests for nv against a headless Neovim that this script starts and stops.
# It never touches your own editor: every call passes the test server's socket.
#
# Usage: tests/run.sh    (needs nvim, perl, lsof, python3; ~20s, mostly
# waiting for file timestamps to change)

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NV_BIN="$ROOT/skills/nvim-remote/scripts/nv"
export NV_SESSION="nvtest-$$"
unset NV_USER_CONFIG NVIM_SOCKET

DIR=$(mktemp -d "${TMPDIR:-/tmp}/nvtest.XXXXXX")
DIR=$(cd "$DIR" && pwd -P)
SOCK=""
PASS=0 FAIL=0

cleanup() {
  [ -n "$SOCK" ] && "$NV_BIN" -s "$SOCK" kill -9 >/dev/null 2>&1
  [ -n "${UI_PID:-}" ] && kill "$UI_PID" 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

nv() { "$NV_BIN" -s "$SOCK" "$@"; }

# Run a command, keeping its output in $OUT and exit status in $RC.
run() { OUT=$("$@" 2>&1); RC=$?; }

ok() { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /'; }

expect_rc() { [ "$RC" -eq "$1" ] && ok "$2" || bad "$2 (exit $RC, wanted $1)" "$OUT"; }
expect_out() { case $OUT in *"$1"*) ok "$2" ;; *) bad "$2 (output lacks: $1)" "$OUT" ;; esac; }
expect_eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got:    $(printf '%q' "$1")"$'\n'"wanted: $(printf '%q' "$2")"; }

file() { tr '\n' '|' < "$DIR/$1"; }
bufl() { nv lua "return table.concat(vim.api.nvim_buf_get_lines(vim.fn.bufnr('$DIR/$1'), 0, -1, false), '|') .. '|'"; }
tick() { printf '%s\n' "$OUT" | sed -n '1s/.* tick=\([0-9]*\).*/\1/p'; }
# Open files in the background, leaving an empty buffer in the window.
open() { local f; for f in "$@"; do nv cmd "edit $DIR/$f" >/dev/null; done; nv cmd enew >/dev/null; }
# File timestamps need to move on for Neovim to notice a change.
later() { sleep 1.1; }

echo "starting test server (session $NV_SESSION)"
"$NV_BIN" start >/dev/null || { echo "could not start nvim"; exit 1; }
SOCK=$("$NV_BIN" attach | awk '{print $3}')
nv cmd 'set noswapfile' >/dev/null

echo "buf read"
printf 'l1\nl2\nl3\n' > "$DIR/a.txt"
open a.txt
run nv buf read "$DIR/nope.txt"; expect_rc 3 "file not open: exit 3"
run nv buf read "$DIR/a.txt"; expect_rc 0 "open file: exit 0"
expect_out "modified=false lines=3" "header"
expect_out "     2  l2" "numbered lines"
run nv buf read "$DIR/a.txt" 2 2; expect_eq "$(printf '%s\n' "$OUT" | sed -n 2,9p)" "     2  l2" "line range"
ln -s "$DIR/a.txt" "$DIR/link.txt"
run nv buf read "$DIR/link.txt"; expect_rc 0 "symlinked path matches"

echo "buf edit"
run nv buf read "$DIR/a.txt"; t=$(tick)
run nv buf edit "$DIR/a.txt" "$t" 2 2 --save <<< "AGENT"
expect_rc 0 "edit and save"; expect_out "saved" "reports saved"
expect_eq "$(file a.txt)" "l1|AGENT|l3|" "saved to disk"
expect_eq "$(nv expr 'bufname()')" '""' "user's window not switched"
t=$(tick)
run nv buf edit "$DIR/a.txt" "$t" 2 1 --save <<< "INS"; expect_eq "$(file a.txt)" "l1|INS|AGENT|l3|" "insert with B = A-1"
t=$(tick)
run nv buf edit "$DIR/a.txt" "$t" 2 2 --save --delete; expect_eq "$(file a.txt)" "l1|AGENT|l3|" "--delete"
t=$(tick)
run nv buf edit "$DIR/a.txt" "$t" 3 3 --save < <(printf 'x\n\n'); expect_eq "$(file a.txt)" "l1|AGENT|x||" "trailing blank line kept"
t=$(tick)
run nv buf edit "$DIR/a.txt" "$t" 1 1 < /dev/null; expect_rc 1 "empty stdin without --delete refused"
run nv buf edit "$DIR/a.txt" "$t" 9 9 <<< "x"; expect_rc 4 "range outside the buffer refused"
nv lua "vim.api.nvim_buf_call(vim.fn.bufnr('$DIR/a.txt'), function() vim.cmd('undo') end)" >/dev/null
expect_eq "$(bufl a.txt)" "l1|AGENT|l3|" "one undo reverts one edit"

echo "changes between read and edit"
printf 'l1\nl2\nl3\n' > "$DIR/b.txt"
open b.txt
run nv buf read "$DIR/b.txt"; t=$(tick)
nv lua "vim.api.nvim_buf_set_lines(vim.fn.bufnr('$DIR/b.txt'), 0, 1, false, {'TYPED'})" >/dev/null
run nv buf edit "$DIR/b.txt" "$t" 2 2 <<< "AGENT"; expect_rc 5 "user typed since read: exit 5"
expect_eq "$(bufl b.txt)" "TYPED|l2|l3|" "nothing edited"

echo "file changed on disk"
printf 'l1\nl2\nl3\n' > "$DIR/c.txt"; printf 'l1\nl2\nl3\n' > "$DIR/d.txt"
printf 'l1\nl2\nl3\n' > "$DIR/e.txt"; printf 'l1\nl2\nl3\n' > "$DIR/f.txt"
open c.txt d.txt e.txt f.txt
nv lua "vim.bo[vim.fn.bufnr('$DIR/d.txt')].autoread = false" >/dev/null
nv lua "vim.api.nvim_buf_set_lines(vim.fn.bufnr('$DIR/e.txt'), 2, 3, false, {'USER'})" >/dev/null
later
printf 'DISK\nl2\nl3\n' > "$DIR/c.txt"; printf 'DISK\nl2\nl3\n' > "$DIR/d.txt"; printf 'DISK\nl2\nl3\n' > "$DIR/e.txt"
rm "$DIR/f.txt"
run nv buf read "$DIR/c.txt"; expect_rc 0 "no unsaved changes: reloaded"; expect_out "     1  DISK" "reads the new contents"
run nv buf read "$DIR/d.txt"; expect_rc 4 "'noautoread': stop"; expect_out "W11" "W11 reported"
run nv buf read "$DIR/d.txt"; expect_rc 0 "'noautoread': second checktime is silent"; t=$(tick)
run nv buf edit "$DIR/d.txt" "$t" 2 2 --save <<< "AGENT"; expect_rc 4 "stale buffer caught before saving"
expect_eq "$(file d.txt)" "DISK|l2|l3|" "disk untouched"
run nv buf read "$DIR/e.txt"; expect_rc 4 "changed on disk and in buffer: stop"; expect_out "W12" "W12 reported"
run nv buf read "$DIR/f.txt"; expect_rc 4 "deleted: stop"; expect_out "E211" "E211 reported"

echo "unsaved changes"
printf 'l1\nl2\nl3\n' > "$DIR/g.txt"
open g.txt
nv lua "vim.api.nvim_buf_set_lines(vim.fn.bufnr('$DIR/g.txt'), 2, 3, false, {'USER'})" >/dev/null
run nv buf read "$DIR/g.txt"; expect_out "modified=true" "reported as modified"; t=$(tick)
run nv buf edit "$DIR/g.txt" "$t" 2 2 --save <<< "AGENT"; expect_rc 4 "--save refused"
run nv buf edit "$DIR/g.txt" "$t" 2 2 <<< "AGENT"; expect_rc 0 "option 2: edit without saving"
expect_eq "$(file g.txt)" "l1|l2|l3|" "option 2: disk untouched"
expect_eq "$(bufl g.txt)" "l1|AGENT|USER|" "option 2: both changes in the buffer"
t=$(tick)
run nv buf save "$DIR/g.txt" "$t"; expect_rc 0 "option 3: save first"
expect_eq "$(file g.txt)" "l1|AGENT|USER|" "option 3: user's work saved"

echo "prompts"
printf 'l1\nl2\nl3\n' > "$DIR/h.txt"
open h.txt
nv lua "vim.api.nvim_buf_set_lines(vim.fn.bufnr('$DIR/h.txt'), 2, 3, false, {'USER'})" >/dev/null
later; printf 'DISK\nl2\nl3\n' > "$DIR/h.txt"
run nv buf read "$DIR/h.txt"; expect_rc 4 "W12 on first check"
run nv buf read "$DIR/h.txt"; expect_rc 0 "W12 is given only once"; t=$(tick)
run nv -t 2 buf save "$DIR/h.txt" "$t"; expect_rc 1 "write hangs at a prompt: times out"
expect_out "yes/no confirm prompt" "timeout names the prompt"
expect_out "nobody attached" "timeout says whose editor"
run "$NV_BIN" -s "$SOCK" doctor; expect_out "WAITING AT A PROMPT" "doctor verdict"
if command -v script >/dev/null; then
  if script -q /dev/null true 2>/dev/null; then
    script -q /dev/null nvim --server "$SOCK" --remote-ui < /dev/null > /dev/null 2>&1 &
  else
    script -qc "nvim --server '$SOCK' --remote-ui" /dev/null < /dev/null > /dev/null 2>&1 &
  fi
  UI_PID=$!; sleep 1
  run "$NV_BIN" -s "$SOCK" doctor; expect_out "with the user attached" "doctor sees an attached UI"
  kill "$UI_PID" 2>/dev/null; wait "$UI_PID" 2>/dev/null; UI_PID=""
else
  echo "  skip  attached UI (no script command)"
fi
nv send n
sleep 0.3
expect_eq "$(nv lua 'return vim.api.nvim_get_mode().mode')" "n" "declining returns to normal mode"
expect_eq "$(file h.txt)" "DISK|l2|l3|" "declined: disk untouched"
expect_eq "$(bufl h.txt)" "l1|l2|USER|" "declined: buffer untouched"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
