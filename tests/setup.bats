#!/usr/bin/env bats
# setup.sh end to end (in a sandboxed HOME with stubbed commands)

load test_helper

setup() {
  common_setup
  SETUP="$REPO_ROOT/setup.sh"
}

# --- help / list / argument errors ---

@test "--help shows usage and sections" {
  run "$SETUP" --help
  assert_status 0
  assert_contains "$output" "Usage: ./setup.sh"
  for s in brew cli gui mas shell configs doom nvchad macos; do
    assert_contains "$output" "  $s "
  done
}

@test "--list prints every section in order" {
  run "$SETUP" --list
  assert_status 0
  [ "$(printf '%s\n' "$output" | awk '{ print $1 }' | tr '\n' ' ')" = "brew cli gui mas shell configs doom nvchad macos " ]
}

@test "--list gui prints casks with descriptions" {
  run "$SETUP" --list gui
  assert_status 0
  assert_contains "$output" "firefox"
  assert_contains "$output" "Firefox"
}

@test "--list configs prints sources and targets" {
  run "$SETUP" --list configs
  assert_contains "$output" "~/.zshrc"
}

@test "--list on a section without items says so" {
  run "$SETUP" --list doom
  assert_status 0
  assert_contains "$output" "no individual items"
}

@test "--list with unknown section fails" {
  run "$SETUP" --list bogus
  assert_status 1
  assert_contains "$output" "unknown section 'bogus'"
}

@test "unknown option fails with usage" {
  run "$SETUP" --bogus
  assert_status 1
  assert_contains "$output" "unknown option '--bogus'"
  assert_contains "$output" "Usage:"
}

@test "--only without a value fails" {
  run "$SETUP" --only
  assert_status 1
  assert_contains "$output" "--only needs a value"
}

@test "--only with unknown section fails" {
  run "$SETUP" -n --only nope
  assert_status 1
  assert_contains "$output" "unknown section 'nope'"
}

@test "nothing selected in the menu exits" {
  answers "n"
  run "$SETUP" -n
  assert_status 1
  assert_contains "$output" "nothing selected"
}

# --- selection ---

@test "--only section runs just that section" {
  run "$SETUP" -n --only macos
  assert_status 0
  assert_contains "$output" "Sections: macos"
  assert_contains "$output" "[dry-run] defaults write"
}

@test "--only a,b runs both in canonical order" {
  run "$SETUP" -n --only macos,configs
  assert_contains "$output" "Sections: configs macos"
}

@test "--only=section form works" {
  run "$SETUP" -n --only=macos
  assert_contains "$output" "Sections: macos"
}

@test "--only section:items installs just those items" {
  run "$SETUP" -n --only gui:firefox,spotify
  assert_status 0
  assert_contains "$output" "[dry-run] brew install --cask firefox"
  assert_contains "$output" "[dry-run] brew install --cask spotify"
  refute_contains "$output" "google-chrome"
}

@test "repeated --only for one section merges items" {
  run "$SETUP" -n --only gui:firefox --only gui:vlc
  assert_contains "$output" "--cask firefox"
  assert_contains "$output" "--cask vlc"
  refute_contains "$output" "--cask spotify"
}

@test "whole section wins over item list" {
  run "$SETUP" -n --only gui:firefox --only gui
  assert_contains "$output" "--cask spotify"
}

@test "unknown items are warned about and skipped" {
  run "$SETUP" -n --only gui:firefox,bogus
  assert_status 0
  assert_contains "$output" "'bogus' is not in the gui list"
  refute_contains "$output" "--cask bogus"
}

@test "--all selects every section and every item" {
  run "$SETUP" -n --all
  assert_status 0
  assert_contains "$output" "Sections: brew cli gui mas shell configs doom nvchad macos"
  # every cask and formula from the lists
  while read -r name; do
    assert_contains "$output" "brew install --cask $name"
  done < <(list_names_of gui/casks.txt)
  while read -r name; do
    assert_contains "$output" "brew install --formula $name"
  done < <(list_names_of cli/formulae.txt)
}

list_names_of() {
  # shellcheck source=../lib/common.sh
  (. "$REPO_ROOT/lib/common.sh" && list_names "$REPO_ROOT/$1")
}

@test "interactive menu: pick sections then items" {
  # sections: 3 = gui, 6 = configs; gui items 1-2; configs: none
  answers "3 6" "1-2" "n"
  run "$SETUP" -n
  assert_status 0
  assert_contains "$output" "Sections: gui"
  assert_contains "$output" "--cask firefox"
  assert_contains "$output" "--cask google-chrome"
  refute_contains "$output" "--cask iterm2"
}

@test "interactive menu: Enter takes all items" {
  answers "6" ""
  run "$SETUP" -n
  assert_contains "$output" "Sections: configs"
  assert_contains "$output" "ln -s $REPO_ROOT/configs/nvim"
  assert_contains "$output" "ln -s $REPO_ROOT/configs/zsh/zshrc"
}

# --- dry-run safety ---

@test "--dry-run --all changes nothing on disk" {
  echo original >"$HOME/.zshrc"
  run "$SETUP" --dry-run --all
  assert_status 0
  assert_contains "$output" "(dry run, nothing was changed)"
  [ "$(cat "$HOME/.zshrc")" = original ]
  [ ! -e "$HOME/.mac-setup-backup" ]
  [ ! -e "$HOME/.config" ]
  # stubs were only ever consulted, never asked to change anything
  refute_called "install"
  refute_called "defaults"
  refute_called "clone"
  refute_called "sudo"
}

# --- real runs (against stubs) ---

@test "real run asks for confirmation and can be cancelled" {
  answers "n"
  run "$SETUP" --only configs
  assert_status 0
  [ ! -e "$HOME/.zshrc" ]
}

@test "real run of configs links files and backs up old ones" {
  echo original >"$HOME/.zshrc"
  run "$SETUP" -y --only configs
  assert_status 0
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/configs/zsh/zshrc" ]
  [ "$(readlink "$HOME/.config/nvim")" = "$REPO_ROOT/configs/nvim" ]
  [ "$(readlink "$HOME/.config/doom")" = "$REPO_ROOT/configs/doom" ]
  [ "$(cat "$HOME"/.mac-setup-backup/*/.zshrc)" = original ]
  assert_contains "$output" "Previous configs were backed up"
  refute_called "sudo"
}

@test "real run of gui caches sudo and installs" {
  stub brew '[ "$1" = list ] && exit 0; exit 0'
  run "$SETUP" -y --only gui:firefox
  assert_status 0
  assert_called "sudo -v"
  assert_called "brew install --cask firefox"
  assert_contains "$output" "1 done, 0 skipped, 0 failed"
}

@test "failures are summarised and don't stop later sections" {
  stub brew '[ "$1" = install ] && exit 1; exit 0'
  run "$SETUP" -y --only gui:firefox --only macos
  assert_status 0
  assert_contains "$output" "Failed:"
  assert_contains "$output" "  - firefox"
  assert_called "defaults write com.apple.dock autohide -bool true"
}
