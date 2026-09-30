# Files changed or deleted on disk: reloads, checktime warnings, stale buffers.
# Sourced by tests/run.sh; helpers are in tests/lib.sh.

mkfile c.txt d.txt e.txt f.txt
open c.txt d.txt e.txt f.txt
nv lua "vim.bo[vim.fn.bufnr('$DIR/d.txt')].autoread = false" >/dev/null
user_types e.txt 3 USER
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
