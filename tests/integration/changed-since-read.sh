# nv buf edit refuses when the buffer changed since the read (exit 5).
# Sourced by tests/run.sh; helpers are in tests/lib.sh.

mkfile b.txt
open b.txt
run nv buf read "$DIR/b.txt"; t=$(tick)
user_types b.txt 1 TYPED
run nv buf edit "$DIR/b.txt" "$t" 2 2 <<< "AGENT"; expect_rc 5 "user typed since read: exit 5"
expect_eq "$(bufl b.txt)" "TYPED|l2|l3|" "nothing edited"
