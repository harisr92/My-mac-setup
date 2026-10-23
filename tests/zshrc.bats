#!/usr/bin/env bats
# configs/zsh/zshrc snippets, run in zsh

load test_helper

setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  common_setup
  ZSHRC="$REPO_ROOT/configs/zsh/zshrc"
}

# block <start regex> <end regex>: print that part of the zshrc
block() { sed -n "/$1/,/$2/p" "$ZSHRC"; }

@test "vterm: chpwd reports the directory with a single 51;A prefix" {
  block '^# vterm' '^fi$' >"$BATS_TEST_TMPDIR/vterm.zsh"
  mkdir -p "$BATS_TEST_TMPDIR/dir"
  run env INSIDE_EMACS=vterm zsh -f -c "source '$BATS_TEST_TMPDIR/vterm.zsh'; cd '$BATS_TEST_TMPDIR/dir'"
  assert_status 0
  dir=$(cd "$BATS_TEST_TMPDIR/dir" && pwd)
  expected=$(printf '\e]51;A%s@%s:%s\e\\' "$(whoami)" "$(hostname)" "$dir")
  [ "$output" = "$expected" ] || { printf 'got:      %q\nexpected: %q\n' "$output" "$expected"; return 1; }
}

@test "vterm: hook is not installed outside vterm" {
  block '^# vterm' '^fi$' >"$BATS_TEST_TMPDIR/vterm.zsh"
  run env -u INSIDE_EMACS zsh -f -c "source '$BATS_TEST_TMPDIR/vterm.zsh'; cd /"
  [ -z "$output" ]
}

@test "completions: compinit is skipped when oh-my-zsh already ran it" {
  block '^# Completions' '^fi$' >"$BATS_TEST_TMPDIR/comp.zsh"
  run zsh -f -c "compdef() { :; }; compinit() { echo COMPINIT; }; source '$BATS_TEST_TMPDIR/comp.zsh'"
  refute_contains "$output" "COMPINIT"
}

@test "completions: compinit runs when oh-my-zsh is missing" {
  block '^# Completions' '^fi$' >"$BATS_TEST_TMPDIR/comp.zsh"
  run zsh -f -c "compinit() { echo COMPINIT; }; source '$BATS_TEST_TMPDIR/comp.zsh'"
  assert_contains "$output" "COMPINIT"
}

@test "docker completions are on fpath before oh-my-zsh loads" {
  docker_line=$(grep -n 'docker/completions' "$ZSHRC" | cut -d: -f1)
  omz_line=$(grep -n 'oh-my-zsh.sh' "$ZSHRC" | cut -d: -f1)
  [ -n "$docker_line" ] && [ "$docker_line" -lt "$omz_line" ]
}

@test "zshrc loads without errors in an empty HOME" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin TERM=dumb zsh -c "source '$ZSHRC'; echo LOADED"
  assert_contains "$output" "LOADED"
  refute_contains "$output" "command not found"
  refute_contains "$output" "no such file"
}
