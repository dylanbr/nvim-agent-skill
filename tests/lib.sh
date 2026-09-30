# Helpers for the tests, sourced by tests/run.sh. Test files are sourced into
# the same shell, one after another, against one shared headless Neovim that
# run.sh resets between files (see reset_server).
#
# Rules for test files:
# - Pass the test server's socket on every call (the nv function does), so the
#   user's own editor is never touched.
# - Work in $DIR, a fresh directory per file.
# - Change only buffer-local settings, or restore any global one you change:
#   the reset wipes buffers but can't detect changed global settings.

NV_BIN="$ROOT/skills/nvim-remote/scripts/nv"
unset NV_USER_CONFIG NVIM_SOCKET

SOCK="" PID="" PIDS="" UI_PID="" SERVERS=0
PASS=0 FAIL=0 FAILED="" CURRENT=""

nv() { "$NV_BIN" -s "$SOCK" "$@"; }

# Run a command, keeping its output in $OUT and exit status in $RC.
run() { OUT=$("$@" 2>&1); RC=$?; }

ok() { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad() {
  FAIL=$((FAIL + 1)); FAILED="$FAILED  $CURRENT: $1"$'\n'
  echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /'
  return 0
}

expect_rc() { [ "$RC" -eq "$1" ] && ok "$2" || bad "$2 (exit $RC, wanted $1)" "$OUT"; }
expect_out() { case $OUT in *"$1"*) ok "$2" ;; *) bad "$2 (output lacks: $1)" "$OUT" ;; esac; }
expect_eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got:    $(printf '%q' "$1")"$'\n'"wanted: $(printf '%q' "$2")"; }

# Create files containing l1, l2, l3.
mkfile() { local f; for f in "$@"; do printf 'l1\nl2\nl3\n' > "$DIR/$f"; done; }
# A file's contents on disk, or its buffer's, with | for each line end.
file() { tr '\n' '|' < "$DIR/$1"; }
bufl() { nv lua "return table.concat(vim.api.nvim_buf_get_lines(vim.fn.bufnr('$DIR/$1'), 0, -1, false), '|') .. '|'"; }
# Change FILE's buffer as if the user typed: replace line N with TEXT.
user_types() { nv lua "vim.api.nvim_buf_set_lines(vim.fn.bufnr('$DIR/$1'), $2 - 1, $2, false, {'$3'})" >/dev/null; }
# The tick from the header of the last `nv buf` output.
tick() { printf '%s\n' "$OUT" | sed -n '1s/.* tick=\([0-9]*\).*/\1/p'; }
# Open files in the background, leaving an empty buffer in the window.
open() { local f; for f in "$@"; do nv cmd "edit $DIR/$f" >/dev/null; done; nv cmd enew >/dev/null; }
# File timestamps need to move on for Neovim to notice a change.
later() { sleep 1.1; }

# --- server ------------------------------------------------------------------

# Start a new test server. Each gets its own socket, so a killed one never
# needs waiting for.
start_server() {
  SERVERS=$((SERVERS + 1))
  export NV_SESSION="nvtest-$$-$SERVERS"
  "$NV_BIN" start >/dev/null || { echo "could not start nvim"; exit 1; }
  SOCK=$("$NV_BIN" attach | awk '{print $3}')
  PID=$(nv expr 'getpid()')
  PIDS="$PIDS $PID"
  nv cmd 'set noswapfile' >/dev/null
}

stop_server() {
  [ -n "$PID" ] && kill -9 "$PID" 2>/dev/null
  [ -n "$SOCK" ] && rm -f "$SOCK"
  PID="" SOCK=""
}

RESET_LUA=$(cat <<'LUA'
vim.cmd('silent! tabonly! | silent! only! | silent! %bwipeout!')
vim.v.warningmsg = ''
vim.v.errmsg = ''
vim.cmd('messages clear')
local m = vim.api.nvim_get_mode()
if m.mode ~= 'n' or m.blocking then return 'mode ' .. m.mode end
local bufs = vim.api.nvim_list_bufs()
if #bufs ~= 1 or vim.api.nvim_buf_get_name(bufs[1]) ~= '' or vim.bo[bufs[1]].modified
    or table.concat(vim.api.nvim_buf_get_lines(bufs[1], 0, -1, false), '\n') ~= '' then
  return 'buffers left over'
end
return 'ok'
LUA
)

# Bring the server back to a known state for the next file: one empty buffer,
# normal mode, no leftover messages. If it can't (stuck at a prompt, waiting
# for keys, anything unexpected), replace it with a new server.
reset_server() {
  local out
  out=$(nv -t 1 lua "$RESET_LUA" 2>&1)
  [ "$out" = ok ] && return
  out=${out#nv: }
  echo "  (server not in a known state: ${out%%[.:] *}; starting a new one)"
  stop_server
  start_server
}

# Kill all servers and check they've all exited.
stop_all() {
  local p i
  stop_server
  [ -n "$UI_PID" ] && kill "$UI_PID" 2>/dev/null
  for p in $PIDS; do kill -9 "$p" 2>/dev/null; done
  for ((i = 0; i < 20; i++)); do
    for p in $PIDS; do kill -0 "$p" 2>/dev/null && break; p=""; done
    [ -z "$p" ] && return 0
    sleep 0.1
  done
  CURRENT=cleanup bad "test servers still running:$PIDS"
}
