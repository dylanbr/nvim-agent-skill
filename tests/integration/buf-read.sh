# nv buf read: exit codes, header, line ranges, symlinks.
# Sourced by tests/run.sh; helpers are in tests/lib.sh.

mkfile a.txt
open a.txt
run nv buf read "$DIR/nope.txt"; expect_rc 3 "file not open: exit 3"
run nv buf read "$DIR/a.txt"; expect_rc 0 "open file: exit 0"
expect_out "modified=false lines=3" "header"
expect_out "     2  l2" "numbered lines"
run nv buf read "$DIR/a.txt" 2 2; expect_eq "$(printf '%s\n' "$OUT" | sed -n 2,9p)" "     2  l2" "line range"
ln -s "$DIR/a.txt" "$DIR/link.txt"
run nv buf read "$DIR/link.txt"; expect_rc 0 "symlinked path matches"
