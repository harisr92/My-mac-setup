# Shared setup for the bats tests.
#
# Every test runs in a sandbox: $HOME is a temp dir, prompts are disabled, and
# anything that could touch the real machine (brew, git, curl, sudo, defaults,
# ...) is replaced by a stub that records its arguments in $STUB_LOG.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

common_setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$STUB_LOG"
  export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

  # No terminal prompts unless a test provides answers
  export MAC_SETUP_TTY_IN=/nonexistent
  export MAC_SETUP_TTY_OUT=/dev/null
  # Never find the real Homebrew or Emacs.app
  export BREW_CANDIDATES=""
  export EMACS_APP_BIN="$BATS_TEST_TMPDIR/no-emacs"
  export DRY_RUN=0 ASSUME_YES=0
  export SHELL=/bin/zsh

  # Safety stubs for everything in /usr/bin that changes the system
  stub defaults
  stub killall
  stub chsh
  stub sudo
  stub curl 'echo "echo curl-script-ran"'
  stub xcode-select
  stub git 'if [ "$1" = clone ]; then mkdir -p "${@: -1}"; fi'
}

# stub <name> [body]: create a fake command that logs "name args" and runs body
stub() {
  local name=$1 body=${2:-true}
  cat >"$STUB_BIN/$name" <<EOF
#!/bin/bash
echo "$name \$*" >>"\$STUB_LOG"
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

unstub() { rm -f "$STUB_BIN/$1"; }

# load_lib: source the library and all section scripts into the test shell
load_lib() {
  ROOT="$REPO_ROOT"
  # shellcheck source=../lib/common.sh
  . "$REPO_ROOT/lib/common.sh"
  local f
  for f in "$REPO_ROOT"/scripts/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
  done
}

# answers <line>...: feed lines to the next prompt(s) via a shared fd
answers() {
  printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/answers"
  exec 4<"$BATS_TEST_TMPDIR/answers"
  export MAC_SETUP_TTY_IN=/dev/fd/4
  export MAC_SETUP_TTY_OUT="$BATS_TEST_TMPDIR/tty-out"
  : >"$MAC_SETUP_TTY_OUT"
  # Also for an already-sourced lib/common.sh
  TTY_IN=$MAC_SETUP_TTY_IN
  TTY_OUT=$MAC_SETUP_TTY_OUT
}

# refute <cmd> [args...]: assert the command fails (bats ignores `! cmd`)
refute() {
  if "$@"; then
    printf 'expected to fail: %s\n' "$*"
    return 1
  fi
}

assert_called() {
  grep -qxF -- "$1" "$STUB_LOG" && return 0
  printf 'expected call: %s\nactual calls:\n' "$1"
  cat "$STUB_LOG"
  return 1
}

refute_called() {
  grep -qF -- "$1" "$STUB_LOG" || return 0
  printf 'unexpected call matching: %s\nactual calls:\n' "$1"
  cat "$STUB_LOG"
  return 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] && return 0
  printf 'expected to contain: %s\nactual:\n%s\n' "$2" "$1"
  return 1
}

refute_contains() {
  [[ "$1" != *"$2"* ]] && return 0
  printf 'expected NOT to contain: %s\nactual:\n%s\n' "$2" "$1"
  return 1
}

assert_status() {
  [ "$status" -eq "$1" ] && return 0
  printf 'expected status %s, got %s\noutput:\n%s\n' "$1" "$status" "$output"
  return 1
}
