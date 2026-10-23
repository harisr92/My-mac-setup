#!/usr/bin/env bats
# bootstrap.sh

load test_helper

setup() {
  common_setup
  export MAC_SETUP_DIR="$HOME/dev/My-mac-setup"
  export MAC_SETUP_REPO="https://example.com/repo.git"
  # git clone creates a checkout whose setup.sh just echoes its arguments
  stub git '
if [ "$1" = clone ]; then
  dest="${@: -1}"
  mkdir -p "$dest/.git"
  printf "#!/bin/bash\necho \"setup.sh ran in \$(dirname \$0) with: \$*\"\n" >"$dest/setup.sh"
  chmod +x "$dest/setup.sh"
fi'
  # Command Line Tools already present unless a test says otherwise
  stub xcode-select '[ "$1" = -p ] && exit 0; exit 0'
}

@test "clones the repo and runs setup.sh with the same arguments" {
  run "$REPO_ROOT/bootstrap.sh" --only gui:firefox
  assert_status 0
  assert_called "git clone $MAC_SETUP_REPO $MAC_SETUP_DIR"
  assert_contains "$output" "setup.sh ran in $MAC_SETUP_DIR with: --only gui:firefox"
  refute_called "xcode-select --install"
}

@test "updates an existing checkout instead of cloning" {
  mkdir -p "$MAC_SETUP_DIR/.git"
  printf '#!/bin/bash\necho existing-setup "$@"\n' >"$MAC_SETUP_DIR/setup.sh"
  chmod +x "$MAC_SETUP_DIR/setup.sh"
  run "$REPO_ROOT/bootstrap.sh" --all
  assert_status 0
  assert_called "git -C $MAC_SETUP_DIR pull --ff-only"
  refute_called "git clone"
  assert_contains "$output" "existing-setup --all"
}

@test "keeps going when the existing checkout can't be updated" {
  mkdir -p "$MAC_SETUP_DIR/.git"
  printf '#!/bin/bash\necho existing-setup\n' >"$MAC_SETUP_DIR/setup.sh"
  chmod +x "$MAC_SETUP_DIR/setup.sh"
  stub git 'exit 1'
  run "$REPO_ROOT/bootstrap.sh"
  assert_status 0
  assert_contains "$output" "could not update"
  assert_contains "$output" "existing-setup"
}

@test "installs Command Line Tools when missing" {
  # -p fails until --install has been run
  stub xcode-select '
marker="$HOME/.clt"
if [ "$1" = --install ]; then touch "$marker"; exit 0; fi
[ -e "$marker" ]'
  run "$REPO_ROOT/bootstrap.sh"
  assert_status 0
  assert_called "xcode-select --install"
}

@test "dry-run doesn't install Command Line Tools" {
  stub xcode-select '[ "$1" = -p ] && exit 1; exit 0'
  run "$REPO_ROOT/bootstrap.sh" --dry-run
  assert_contains "$output" "[dry-run] xcode-select --install"
  refute_called "xcode-select --install"
}

@test "dry-run clones into a temp dir, not MAC_SETUP_DIR" {
  run "$REPO_ROOT/bootstrap.sh" -n
  assert_status 0
  [ ! -e "$MAC_SETUP_DIR" ]
  assert_contains "$output" "with: -n"
  refute_contains "$output" "ran in $MAC_SETUP_DIR"
}

@test "dry-run without git stops after explaining" {
  stub xcode-select '[ "$1" = -p ] && exit 1; exit 0'
  # hide git: PATH without /usr/bin
  ln -s /bin/bash "$STUB_BIN/bash"
  for c in dirname mkdir mktemp; do ln -sf "/usr/bin/$c" "$STUB_BIN/$c" 2>/dev/null || ln -sf "/bin/$c" "$STUB_BIN/$c"; done
  unstub git
  PATH="$STUB_BIN:/bin" run "$REPO_ROOT/bootstrap.sh" --dry-run
  assert_status 0
  assert_contains "$output" "[dry-run] git clone"
  assert_contains "$output" "git is not available yet"
}

@test "dry-run with an existing checkout prints the pull instead of running it" {
  mkdir -p "$MAC_SETUP_DIR/.git"
  printf '#!/bin/bash\necho existing-setup "$@"\n' >"$MAC_SETUP_DIR/setup.sh"
  chmod +x "$MAC_SETUP_DIR/setup.sh"
  run "$REPO_ROOT/bootstrap.sh" --dry-run
  assert_status 0
  assert_contains "$output" "[dry-run] git -C $MAC_SETUP_DIR pull --ff-only"
  refute_called "git"
  assert_contains "$output" "existing-setup --dry-run"
}

@test "dry-run treats /usr/bin/git as unusable until the CLT are installed" {
  [ -x /usr/bin/git ] || skip "no /usr/bin/git"
  unstub git
  stub xcode-select '[ "$1" = -p ] && exit 1; exit 0'
  run "$REPO_ROOT/bootstrap.sh" --dry-run
  assert_status 0
  assert_contains "$output" "git is not available yet"
  [ ! -e "$MAC_SETUP_DIR" ]
}

@test "gives up waiting for the CLT after 30 minutes" {
  stub xcode-select '[ "$1" = -p ] && exit 1; exit 0'
  stub sleep
  run "$REPO_ROOT/bootstrap.sh"
  assert_status 1
  assert_contains "$output" "still not installed after 30 minutes"
  [ "$(grep -c '^sleep 10$' "$STUB_LOG")" -eq 180 ]
  refute_called "git clone"
}
