#!/usr/bin/env bats
# ci/check-packages.sh, against fake Homebrew metadata (no network)

load test_helper

setup() {
  JQ=$(PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v jq) || skip "jq not installed"
  common_setup
  ln -s "$JQ" "$STUB_BIN/jq"

  # Lists to check live in a fixture root
  export MAC_SETUP_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$MAC_SETUP_ROOT/cli" "$MAC_SETUP_ROOT/gui"
  printf 'some/tap\n' >"$MAC_SETUP_ROOT/cli/taps.txt"
  : >"$MAC_SETUP_ROOT/cli/formulae.txt"
  : >"$MAC_SETUP_ROOT/gui/casks.txt"
  : >"$MAC_SETUP_ROOT/gui/mas.txt"

  # brew info --json=v2 --formula|--cask <name> prints $META/<name with / as _>.json
  export META="$BATS_TEST_TMPDIR/meta"
  mkdir -p "$META"
  stub brew 'f="$META/$(printf "%s" "${@: -1}" | tr / _).json"; [ -f "$f" ] && cat "$f"'
  # App Store lookup: ids listed in $META/mas exist
  stub curl 'id=${@: -1}; id=${id##*id=}; if grep -qx "$id" "$META/mas" 2>/dev/null; then echo "{\"resultCount\":1}"; else echo "{\"resultCount\":0}"; fi'

  CHECK="$REPO_ROOT/ci/check-packages.sh"
}

# formula <listed name> <name> <full_name> <tap> [deprecated] [disabled] [reason]
formula() {
  echo "$1" >>"$MAC_SETUP_ROOT/cli/formulae.txt"
  cat >"$META/$(printf '%s' "$1" | tr / _).json" <<EOF
{"formulae":[{"name":"$2","full_name":"$3","tap":"$4","deprecated":${5:-false},"disabled":${6:-false},"deprecation_reason":null,"disable_reason":${7:-null}}],"casks":[]}
EOF
}

# cask <listed name> <token> <tap> [sha256] [url] [deprecated] [disabled] [reason]
cask() {
  echo "$1" >>"$MAC_SETUP_ROOT/gui/casks.txt"
  cat >"$META/$(printf '%s' "$1" | tr / _).json" <<EOF
{"formulae":[],"casks":[{"token":"$2","full_token":"$2","tap":"$3","sha256":"${4:-abc123}","url":"${5:-https://example.com/app.dmg}","deprecated":${6:-false},"disabled":${7:-false},"deprecation_reason":null,"disable_reason":${8:-null}}]}
EOF
}

@test "healthy lists pass" {
  formula jq jq jq homebrew/core
  formula some/tap/tool tool some/tap/tool some/tap
  cask firefox firefox homebrew/cask
  echo 123 >"$META/mas"
  echo "123  # App" >"$MAC_SETUP_ROOT/gui/mas.txt"
  run "$CHECK"
  assert_status 0
  assert_contains "$output" "0 error(s), 0 warning(s)"
}

@test "missing formula and cask fail" {
  echo nope >>"$MAC_SETUP_ROOT/cli/formulae.txt"
  echo nada >>"$MAC_SETUP_ROOT/gui/casks.txt"
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "nope: not found in Homebrew"
  assert_contains "$output" "nada: not found in Homebrew"
}

@test "disabled package fails with the reason" {
  cask darktable darktable homebrew/cask abc https://x.com/a.dmg false true '"fails_gatekeeper_check"'
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "darktable: is disabled in Homebrew (fails_gatekeeper_check)"
}

@test "deprecated package only warns" {
  formula old old old homebrew/core true
  run "$CHECK"
  assert_status 0
  assert_contains "$output" "old: is deprecated in Homebrew"
  assert_contains "$output" "0 error(s), 1 warning(s)"
}

@test "renamed cask fails and names the new token" {
  cask emacs emacs-app homebrew/cask
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "emacs: is now 'emacs-app'"
}

@test "formula migrated out of a tap fails" {
  formula gitguardian/tap/ggshield ggshield ggshield homebrew/core
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "is now 'ggshield'"
}

@test "package from an undeclared tap fails" {
  formula evil/tap/x x evil/tap/x evil/tap
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "comes from tap 'evil/tap', which isn't in cli/taps.txt"
}

@test "cask over plain http fails" {
  cask app app homebrew/cask abc http://example.com/app.dmg
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "insecure URL: http://example.com/app.dmg"
}

@test "cask without checksum only warns" {
  cask chrome chrome homebrew/cask no_check
  run "$CHECK"
  assert_status 0
  assert_contains "$output" "chrome: has no checksum"
}

@test "unknown App Store id fails" {
  echo "999  # Ghost" >"$MAC_SETUP_ROOT/gui/mas.txt"
  run "$CHECK"
  assert_status 1
  assert_contains "$output" "999: no App Store app with this id"
}

@test "unreachable App Store only warns" {
  stub curl 'exit 6'
  echo "123  # App" >"$MAC_SETUP_ROOT/gui/mas.txt"
  run "$CHECK"
  assert_status 0
  assert_contains "$output" "couldn't reach the App Store"
}

@test "GitHub annotations point at the right line" {
  formula jq jq jq homebrew/core
  echo nope >>"$MAC_SETUP_ROOT/cli/formulae.txt"
  GITHUB_ACTIONS=true run "$CHECK"
  assert_contains "$output" "::error file=cli/formulae.txt,line=2::nope: not found in Homebrew"
}

@test "fails clearly without jq" {
  rm "$STUB_BIN/jq"
  # /usr/bin has jq on recent macOS, so expose only the basic tools
  tools="$BATS_TEST_TMPDIR/tools"
  mkdir -p "$tools"
  for c in dirname date tr awk cut; do ln -s "/usr/bin/$c" "$tools/$c"; done
  PATH="$tools:$STUB_BIN" run /bin/bash "$CHECK"
  assert_status 1
  assert_contains "$output" "jq is required"
}
