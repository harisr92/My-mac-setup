#!/usr/bin/env bats
# scripts/brew.sh: brew, cli, gui and mas sections

load test_helper

setup() {
  common_setup
  load_lib
}

# fake_brew [installed formulae] [installed casks] [taps]
fake_brew() {
  stub brew "
case \"\$1 \$2\" in
  'list --formula') printf '%s\n' $1 ;;
  'list --cask') printf '%s\n' $2 ;;
  'tap ') printf '%s\n' $3 ;;
esac"
}

# --- load_brew_env / require_brew ---

@test "load_brew_env: fails when no brew is found" {
  BREW_CANDIDATES="$BATS_TEST_TMPDIR/nope"
  refute load_brew_env
}

@test "load_brew_env: evals shellenv of the first brew found" {
  mkdir -p "$BATS_TEST_TMPDIR/hb"
  printf '#!/bin/bash\necho "export FROM_BREW=yes"\n' >"$BATS_TEST_TMPDIR/hb/brew"
  chmod +x "$BATS_TEST_TMPDIR/hb/brew"
  BREW_CANDIDATES="$BATS_TEST_TMPDIR/missing $BATS_TEST_TMPDIR/hb/brew"
  load_brew_env
  [ "$FROM_BREW" = yes ]
}

@test "require_brew: ok when brew is on PATH" {
  fake_brew
  require_brew
}

@test "require_brew: fails without brew" {
  run require_brew
  assert_status 1
  assert_contains "$output" "Homebrew is not installed"
}

@test "require_brew: dry-run continues without brew" {
  DRY_RUN=1
  run require_brew
  assert_status 0
  assert_contains "$output" "showing what would be installed"
}

# --- section_brew ---

@test "section_brew: skips when brew exists" {
  fake_brew
  run section_brew
  assert_contains "$output" "Homebrew (already installed)"
  refute_called "curl"
}

@test "section_brew: runs the official installer when missing" {
  # The installer "creates" brew where load_brew_env looks for it
  hb="$BATS_TEST_TMPDIR/hb/brew"
  BREW_CANDIDATES="$hb"
  stub curl "echo 'mkdir -p $(dirname "$hb"); printf \"#!/bin/bash\\necho true\\n\" > $hb; chmod +x $hb'"
  section_brew >/dev/null
  assert_called "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  [ -x "$hb" ]
  [ "$DONE_ITEMS" = "Homebrew"$'\n' ]
}

@test "section_brew: dies if brew is still missing after install" {
  run section_brew
  assert_status 1
  assert_contains "$output" "Homebrew install failed"
}

@test "section_brew: dry-run only prints the installer" {
  DRY_RUN=1
  run section_brew
  assert_status 0
  assert_contains "$output" "[dry-run] NONINTERACTIVE=1"
  refute_called "curl"
}

# --- section_cli ---

@test "section_cli: taps missing taps and installs missing formulae" {
  fake_brew "git"
  section_cli git jq hashicorp/tap/terraform >/dev/null
  assert_called "brew tap hashicorp/tap"
  refute_called "brew install --formula git"
  assert_called "brew install --formula jq"
  assert_called "brew install --formula hashicorp/tap/terraform"
}

@test "section_cli: skips taps that are already tapped" {
  fake_brew "" "" "hashicorp/tap"
  section_cli >/dev/null
  refute_called "brew tap hashicorp/tap"
}

@test "section_cli: tapped formula counts as installed by its short name" {
  fake_brew "terraform"
  run section_cli hashicorp/tap/terraform
  refute_called "brew install"
  assert_contains "$output" "hashicorp/tap/terraform (already done)"
}

@test "section_cli: records failed installs and keeps going" {
  stub brew '[ "$1" = install ] && [ "$3" = bad ] && exit 1; exit 0'
  section_cli bad good >/dev/null 2>&1 || true
  [ "$FAILED_ITEMS" = "bad"$'\n' ]
  assert_contains "$DONE_ITEMS" "good"
}

@test "section_cli: does nothing without brew" {
  run section_cli jq
  assert_status 0
  refute_called "install"
}

@test "section_cli: dry-run without brew lists installs" {
  DRY_RUN=1
  run section_cli jq
  assert_contains "$output" "[dry-run] brew tap hashicorp/tap"
  assert_contains "$output" "[dry-run] brew install --formula jq"
}

# --- section_gui ---

@test "section_gui: installs missing casks only" {
  fake_brew "" "firefox"
  section_gui firefox spotify >/dev/null
  refute_called "brew install --cask firefox"
  assert_called "brew install --cask spotify"
}

# --- section_mas ---

@test "section_mas: installs mas first when missing" {
  fake_brew
  section_mas >/dev/null 2>&1
  assert_called "brew install mas"
}

@test "section_mas: installs missing apps, skips installed" {
  fake_brew
  stub mas '[ "$1" = list ] && echo "497799835 Xcode (16.0)"; exit 0'
  run section_mas 497799835 361309726
  refute_called "mas install 497799835"
  assert_called "mas install 361309726"
  assert_contains "$output" "app store 361309726 (Pages)"
}

@test "section_mas: dry-run without mas warns instead of installing" {
  DRY_RUN=1
  run section_mas 361309726
  assert_contains "$output" "mas not installed yet"
  assert_contains "$output" "[dry-run] mas install 361309726"
}

@test "section_mas: stops if mas can't be installed" {
  stub brew '[ "$1" = install ] && exit 1; exit 0'
  run section_mas 361309726
  assert_contains "$output" "mas failed"
  refute_called "mas install"
}
