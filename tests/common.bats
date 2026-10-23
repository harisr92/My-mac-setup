#!/usr/bin/env bats
# lib/common.sh

load test_helper

setup() {
  common_setup
  load_lib
}

# --- have / in_words / expand_home ---

@test "have: finds commands on PATH" {
  stub mytool
  have mytool
  refute have definitely-not-a-command
}

@test "in_words: matches whole words only" {
  in_words b "a b c"
  in_words a "a"
  refute in_words d "a b c"
  refute in_words fire "firefox chrome"
  refute in_words a ""
}

@test "expand_home: expands leading ~ only" {
  [ "$(expand_home "~")" = "$HOME" ]
  [ "$(expand_home "~/.zshrc")" = "$HOME/.zshrc" ]
  [ "$(expand_home "/etc/~x")" = "/etc/~x" ]
  [ "$(expand_home "rel/path")" = "rel/path" ]
}

# --- run_cmd / run_sh ---

@test "run_cmd: executes the command" {
  run run_cmd touch "$BATS_TEST_TMPDIR/made"
  assert_status 0
  [ -f "$BATS_TEST_TMPDIR/made" ]
}

@test "run_cmd: returns the command's exit status" {
  run run_cmd false
  assert_status 1
}

@test "run_cmd: dry-run prints quoted command and does nothing" {
  DRY_RUN=1
  run run_cmd touch "$BATS_TEST_TMPDIR/a file"
  assert_status 0
  assert_contains "$output" "[dry-run] touch"
  assert_contains "$output" 'a\ file'
  [ ! -e "$BATS_TEST_TMPDIR/a file" ]
}

@test "run_sh: runs a shell snippet" {
  run run_sh "echo hi > '$BATS_TEST_TMPDIR/out' && echo done"
  assert_status 0
  [ "$output" = "done" ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = hi ]
}

@test "run_sh: dry-run prints the snippet unchanged" {
  DRY_RUN=1
  run run_sh 'X=1 foo | bar'
  [ "$output" = "[dry-run] X=1 foo | bar" ]
}

@test "run_cmd: delegates to run_sh when given run_sh" {
  DRY_RUN=1
  run run_cmd run_sh 'a | b'
  [ "$output" = "[dry-run] a | b" ]
}

# --- track / mark_* ---

@test "track: records success" {
  track "thing" true >/dev/null
  [ "$DONE_ITEMS" = "thing"$'\n' ]
  [ -z "$FAILED_ITEMS" ]
}

@test "track: records failure without exiting" {
  track "thing" false 2>/dev/null || true
  [ "$FAILED_ITEMS" = "thing"$'\n' ]
  [ -z "$DONE_ITEMS" ]
}

@test "track: dry-run counts as done but prints only the command" {
  DRY_RUN=1
  run track "label" echo x
  [ "$output" = "[dry-run] echo x" ]
}

@test "mark_skipped: records and prints the reason" {
  run mark_skipped "pkg" "because"
  assert_contains "$output" "pkg (because)"
  mark_skipped "pkg" >/dev/null
  [ "$SKIPPED_ITEMS" = "pkg"$'\n' ]
}

@test "mark_skipped: default reason is 'already done'" {
  run mark_skipped "pkg"
  assert_contains "$output" "pkg (already done)"
}

@test "die: prints error and exits 1" {
  run die "boom"
  assert_status 1
  assert_contains "$output" "boom"
}

# --- read_list / list_names ---

@test "read_list: parses names and descriptions, skips comments and blanks" {
  cat >"$BATS_TEST_TMPDIR/list" <<'EOF'
# a comment

alpha           # First thing
  beta   #   Second thing
gamma
tap/x/delta     # Tapped
EOF
  run read_list "$BATS_TEST_TMPDIR/list"
  assert_status 0
  [ "${lines[0]}" = $'alpha\tFirst thing' ]
  [ "${lines[1]}" = $'beta\tSecond thing' ]
  [ "${lines[2]}" = $'gamma\t' ]
  [ "${lines[3]}" = $'tap/x/delta\tTapped' ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "list_names: names only" {
  printf 'a # x\nb\n# c\n' >"$BATS_TEST_TMPDIR/list"
  run list_names "$BATS_TEST_TMPDIR/list"
  [ "$output" = $'a\nb' ]
}

# --- choose ---

menu() { printf 'one\tFirst\ntwo\tSecond\nthree\tThird\nfour\tFourth\n'; }

@test "choose: no terminal selects everything" {
  run bash -c ". '$REPO_ROOT/lib/common.sh'; printf 'a\tA\nb\tB\n' | choose t"
  [ "$output" = $'a\nb' ]
}

@test "choose: ASSUME_YES selects everything without prompting" {
  answers "1"
  ASSUME_YES=1
  run choose t < <(menu)
  [ "$output" = $'one\ntwo\nthree\nfour' ]
}

@test "choose: empty input selects nothing" {
  run choose t </dev/null
  [ -z "$output" ]
}

@test "choose: Enter selects all" {
  answers ""
  run choose t < <(menu)
  [ "$output" = $'one\ntwo\nthree\nfour' ]
}

@test "choose: 'a' selects all" {
  answers "a"
  run choose t < <(menu)
  [ "${#lines[@]}" -eq 4 ]
}

@test "choose: 'n' selects none" {
  answers "n"
  run choose t < <(menu)
  [ -z "$output" ]
}

@test "choose: numbers, ranges and commas" {
  answers "1,3-4"
  run choose t < <(menu)
  [ "$output" = $'one\nthree\nfour' ]
}

@test "choose: ignores out-of-range and invalid entries" {
  answers "2 9 0 x"
  run choose t < <(menu)
  assert_contains "$output" "ignoring 'x'"
  [ "$(printf '%s\n' "$output" | grep -vc ignoring)" -eq 1 ]
  assert_contains "$output" "two"
}

@test "choose: shows the numbered menu on the terminal" {
  answers ""
  choose "My title" < <(menu) >/dev/null
  out=$(cat "$MAC_SETUP_TTY_OUT")
  assert_contains "$out" "My title"
  assert_contains "$out" "1) one"
  assert_contains "$out" "Second"
}

@test "choose: uses fzf when available and returns first column" {
  stub fzf 'cat >/dev/null; printf "two                              Second\nfour                             Fourth\n"'
  answers ""
  run choose t < <(menu)
  [ "$output" = $'two\nfour' ]
  assert_contains "$(cat "$STUB_LOG")" "--multi"
}

@test "choose: fzf cancelled selects nothing" {
  stub fzf 'cat >/dev/null; exit 130'
  answers ""
  run choose t < <(menu)
  [ -z "$output" ]
}

# --- confirm ---

@test "confirm: defaults to yes" {
  answers ""
  confirm "ok?"
  assert_contains "$(cat "$MAC_SETUP_TTY_OUT")" "ok? [Y/n]"
}

@test "confirm: n means no" {
  answers "n"
  refute confirm "ok?"
}

@test "confirm: ASSUME_YES and no terminal both mean yes" {
  ASSUME_YES=1
  confirm "ok?"
  ASSUME_YES=0
  confirm "ok?"
}

# --- backup_and_link ---

@test "backup_and_link: creates link and parent dirs" {
  echo src >"$BATS_TEST_TMPDIR/src"
  backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/a/b/target" >/dev/null
  [ "$(readlink "$HOME/a/b/target")" = "$BATS_TEST_TMPDIR/src" ]
  [ ! -d "$BACKUP_DIR" ]
}

@test "backup_and_link: backs up an existing file" {
  echo src >"$BATS_TEST_TMPDIR/src"
  echo old >"$HOME/.zshrc"
  backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/.zshrc" >/dev/null
  [ "$(readlink "$HOME/.zshrc")" = "$BATS_TEST_TMPDIR/src" ]
  [ "$(cat "$BACKUP_DIR/.zshrc")" = old ]
}

@test "backup_and_link: backs up an existing directory keeping its path" {
  mkdir -p "$BATS_TEST_TMPDIR/src" "$HOME/.config/nvim"
  echo old >"$HOME/.config/nvim/init.lua"
  backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/.config/nvim" >/dev/null
  [ -L "$HOME/.config/nvim" ]
  [ "$(cat "$BACKUP_DIR/.config/nvim/init.lua")" = old ]
}

@test "backup_and_link: replaces a symlink pointing elsewhere" {
  echo src >"$BATS_TEST_TMPDIR/src"
  ln -s /elsewhere "$HOME/.zshrc"
  backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/.zshrc" >/dev/null
  [ "$(readlink "$HOME/.zshrc")" = "$BATS_TEST_TMPDIR/src" ]
  [ "$(readlink "$BACKUP_DIR/.zshrc")" = /elsewhere ]
}

@test "backup_and_link: skips a correct link" {
  echo src >"$BATS_TEST_TMPDIR/src"
  ln -s "$BATS_TEST_TMPDIR/src" "$HOME/.zshrc"
  run backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/.zshrc"
  assert_contains "$output" "already linked"
  [ ! -d "$BACKUP_DIR" ]
}

@test "backup_and_link: dry-run changes nothing" {
  DRY_RUN=1
  echo old >"$HOME/.zshrc"
  run backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/.zshrc"
  assert_contains "$output" "[dry-run] mv"
  assert_contains "$output" "[dry-run] ln -s"
  [ ! -L "$HOME/.zshrc" ]
  [ "$(cat "$HOME/.zshrc")" = old ]
  [ ! -d "$BACKUP_DIR" ]
}

# --- git_clone ---

@test "git_clone: clones a missing repo" {
  git_clone https://example.com/r "$HOME/r" >/dev/null
  assert_called "git clone --depth 1 https://example.com/r $HOME/r"
  [ "$DONE_ITEMS" = "clone https://example.com/r"$'\n' ]
}

@test "git_clone: skips an existing directory" {
  mkdir -p "$HOME/r"
  run git_clone https://example.com/r "$HOME/r"
  assert_contains "$output" "already exists"
  refute_called "git clone"
}

# --- print_summary ---

@test "print_summary: counts and lists failures" {
  mark_done a >/dev/null
  mark_done b >/dev/null
  mark_skipped c >/dev/null
  mark_failed d 2>/dev/null
  run print_summary
  assert_contains "$output" "2 done, 1 skipped, 1 failed"
  assert_contains "$output" "  - d"
}

@test "print_summary: dry-run wording" {
  DRY_RUN=1
  mark_done a
  run print_summary
  assert_contains "$output" "dry run, nothing was changed"
  assert_contains "$output" "1 would be done"
}

@test "print_summary: mentions backup dir when used" {
  mkdir -p "$BACKUP_DIR"
  run print_summary
  assert_contains "$output" "backed up to $BACKUP_DIR"
}

@test "track: returns the command's exit status" {
  run track "x" false
  assert_status 1
  run track "x" true
  assert_status 0
}

# --- backup_path ---

@test "backup_path: moves a path into BACKUP_DIR keeping its place under HOME" {
  mkdir -p "$HOME/.config/emacs"
  echo x >"$HOME/.config/emacs/init.el"
  backup_path "$HOME/.config/emacs"
  [ ! -e "$HOME/.config/emacs" ]
  [ "$(cat "$BACKUP_DIR/.config/emacs/init.el")" = x ]
}

@test "backup_path: fails when the move fails" {
  echo x >"$HOME/.zshrc"
  stub mv 'exit 1'
  run backup_path "$HOME/.zshrc"
  assert_status 1
}

@test "backup_path: dry-run leaves the file in place" {
  DRY_RUN=1
  echo x >"$HOME/.zshrc"
  run backup_path "$HOME/.zshrc"
  assert_contains "$output" "[dry-run] mv $HOME/.zshrc $BACKUP_DIR/.zshrc"
  [ -f "$HOME/.zshrc" ]
}

@test "backup_and_link: failed backup doesn't link" {
  echo old >"$HOME/.zshrc"
  stub mv 'exit 1'
  run backup_and_link "$BATS_TEST_TMPDIR/src" "$HOME/.zshrc"
  assert_status 1
  assert_contains "$output" "backup $HOME/.zshrc failed"
  [ ! -L "$HOME/.zshrc" ]
}
