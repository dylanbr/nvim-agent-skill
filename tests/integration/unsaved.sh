# Buffers with unsaved changes: --save refused, options 2 and 3.
# Sourced by tests/run.sh; helpers are in tests/lib.sh.

mkfile g.txt
open g.txt
user_types g.txt 3 USER
run nv buf read "$DIR/g.txt"; expect_out "modified=true" "reported as modified"; t=$(tick)
run nv buf edit "$DIR/g.txt" "$t" 2 2 --save <<< "AGENT"; expect_rc 4 "--save refused"
run nv buf edit "$DIR/g.txt" "$t" 2 2 <<< "AGENT"; expect_rc 0 "option 2: edit without saving"
expect_eq "$(file g.txt)" "l1|l2|l3|" "option 2: disk untouched"
expect_eq "$(bufl g.txt)" "l1|AGENT|USER|" "option 2: both changes in the buffer"
t=$(tick)
run nv buf save "$DIR/g.txt" "$t"; expect_rc 0 "option 3: save first"
expect_eq "$(file g.txt)" "l1|AGENT|USER|" "option 3: user's work saved"
