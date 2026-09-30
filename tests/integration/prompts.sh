# A write that hits the "file changed" prompt: timeout, doctor, declining.
# Sourced by tests/run.sh; helpers are in tests/lib.sh.

mkfile h.txt
open h.txt
user_types h.txt 3 USER
later; printf 'DISK\nl2\nl3\n' > "$DIR/h.txt"
run nv buf read "$DIR/h.txt"; expect_rc 4 "W12 on first check"
run nv buf read "$DIR/h.txt"; expect_rc 0 "W12 is given only once"; t=$(tick)
run nv -t 2 buf save "$DIR/h.txt" "$t"; expect_rc 1 "write hangs at a prompt: times out"
expect_out "yes/no confirm prompt" "timeout names the prompt"
expect_out "nobody attached" "timeout says whose editor"
run nv doctor; expect_out "WAITING AT A PROMPT" "doctor verdict"
# Attach a real UI through a pseudo-terminal (script), and check doctor sees it.
if command -v script >/dev/null; then
  case $(uname) in
    Darwin|*BSD) script -q /dev/null nvim --server "$SOCK" --remote-ui < /dev/null > /dev/null 2>&1 & ;;
    *) script -qc "nvim --server '$SOCK' --remote-ui" /dev/null < /dev/null > /dev/null 2>&1 & ;;
  esac
  UI_PID=$!
  for ((i = 0; i < 50; i++)); do
    ps -A -o command= | grep -F -- "--server $SOCK" | grep -q -- --remote-ui && break
    sleep 0.1
  done
  run nv doctor; expect_out "with the user attached" "doctor sees an attached UI"
  kill "$UI_PID" 2>/dev/null; wait "$UI_PID" 2>/dev/null; UI_PID=""
else
  echo "  skip  attached UI (no script command)"
fi
nv send n
sleep 0.3
expect_eq "$(nv lua 'return vim.api.nvim_get_mode().mode')" "n" "declining returns to normal mode"
expect_eq "$(file h.txt)" "DISK|l2|l3|" "declined: disk untouched"
expect_eq "$(bufl h.txt)" "l1|l2|USER|" "declined: buffer untouched"
