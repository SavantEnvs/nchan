# nchan_get_rest_of_line_in_cstr: infinite loop when the key occurs mid-line

`src/util/nchan_util.c` `nchan_get_rest_of_line_in_cstr()` searches with `strstr(cstr, line_start)`
on every iteration instead of from `cur`, and when the match is not at a line start it does
`cur = strchr(cur, '\n')`, which points at the same newline forever (it never steps past it).
Any text where `slave0:` / `master_host:` / `master_port:` occurs in the middle of a line that is
followed by a newline never terminates.

- Impact: the nchan worker spins at 100% CPU forever when a Redis server's `INFO` reply contains such
  a line (`parse_info_master`/`parse_info_slaves`; also `nchan_cstr_match_line`).
- Reproducer: `repro` (`x slave0:\n`); `timeout 10 /mayhem/fuzz_info-standalone repro` exits 124.
- Fix: search from `cur` (`strstr(cur, line_start)`) and advance past the newline
  (`cur = strchr(cur, '\n'); if(cur) cur++;`).
