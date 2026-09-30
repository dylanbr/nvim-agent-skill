# nv buf edit: replacing, inserting, deleting, saving, and one undo step per edit.
# Sourced by tests/run.sh; helpers are in tests/lib.sh.

mkfile a.txt
open a.txt
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
