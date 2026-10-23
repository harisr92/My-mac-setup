#!/usr/bin/env bats
# scripts/configs.sh, shell.sh, doom.sh, nvchad.sh, macos.sh

load test_helper

setup() {
  common_setup
  load_lib
}

# --- configs ---

@test "link_target: looks up the target for a source" {
  [ "$(link_target zsh/zshrc)" = "~/.zshrc" ]
  [ "$(link_target nvim)" = "~/.config/nvim" ]
  [ -z "$(link_target nope)" ]
}

@test "section_configs: links every given source into HOME" {
  section_configs zsh/zshrc git/ignore nvim >/dev/null
  [ "$(readlink "$HOME/.zshrc")" = "$REPO_ROOT/configs/zsh/zshrc" ]
  [ "$(readlink "$HOME/.config/git/ignore")" = "$REPO_ROOT/configs/git/ignore" ]
  [ "$(readlink "$HOME/.config/nvim")" = "$REPO_ROOT/configs/nvim" ]
  [ ! -e "$HOME/.gitconfig" ]
}

@test "section_configs: warns about unknown sources" {
  run section_configs nope
  assert_contains "$output" "no target for nope"
}

@test "section_configs: second run skips everything" {
  section_configs zsh/zshrc >/dev/null
  run section_configs zsh/zshrc
  assert_contains "$output" "already linked"
}

# --- shell ---

@test "section_shell: fresh install" {
  SHELL=/bin/bash
  run section_shell
  assert_status 0
  assert_called "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  assert_contains "$output" "curl-script-ran"
  custom="$HOME/.oh-my-zsh/custom"
  assert_called "git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions $custom/plugins/zsh-autosuggestions"
  assert_called "git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting $custom/plugins/zsh-syntax-highlighting"
  assert_called "git clone --depth 1 https://github.com/spaceship-prompt/spaceship-prompt $custom/themes/spaceship-prompt"
  [ "$(readlink "$custom/themes/spaceship.zsh-theme")" = "$custom/themes/spaceship-prompt/spaceship.zsh-theme" ]
  assert_called "chsh -s /bin/zsh"
}

@test "section_shell: already set up skips everything" {
  custom="$HOME/.oh-my-zsh/custom"
  mkdir -p "$custom/plugins/zsh-autosuggestions" "$custom/plugins/zsh-syntax-highlighting" "$custom/themes/spaceship-prompt"
  ln -s x "$custom/themes/spaceship.zsh-theme"
  run section_shell
  assert_contains "$output" "oh-my-zsh (already done)"
  refute_called "curl"
  refute_called "git clone"
  refute_called "chsh"
}

# --- doom ---

@test "section_doom: fails without git" {
  have() { [ "$1" != git ] && command -v "$1" >/dev/null; }
  run section_doom
  assert_contains "$output" "git is required"
  refute_called "git clone"
}

@test "section_doom: fresh install clones doom and runs install" {
  stub emacs
  stub rg
  run section_doom
  assert_called "git clone --depth 1 https://github.com/doomemacs/doomemacs $HOME/.config/emacs"
  # git stub only creates the dir, so the doom binary is reported as failing
  assert_contains "$output" "doom install"
  [ "$(readlink "$HOME/.config/doom")" = "$REPO_ROOT/configs/doom" ]
}

@test "section_doom: existing doom runs sync" {
  stub emacs
  stub rg
  mkdir -p "$HOME/.config/emacs/bin" "$HOME/.config/doom"
  printf '#!/bin/bash\necho "doom $*" >>"$STUB_LOG"\n' >"$HOME/.config/emacs/bin/doom"
  chmod +x "$HOME/.config/emacs/bin/doom"
  run section_doom
  assert_called "doom sync"
  refute_called "git clone"
  # an existing doom config dir is left alone (configs section owns it)
  [ ! -L "$HOME/.config/doom" ]
}

@test "section_doom: backs up a non-doom ~/.config/emacs" {
  stub emacs
  stub rg
  mkdir -p "$HOME/.config/emacs"
  echo mine >"$HOME/.config/emacs/init.el"
  section_doom >/dev/null 2>&1 || true
  [ "$(cat "$BACKUP_DIR/.config/emacs/init.el")" = mine ]
}

@test "section_doom: warns about missing emacs and ripgrep" {
  run section_doom
  assert_contains "$output" "Emacs not found"
  assert_contains "$output" "ripgrep not found"
}

@test "section_doom: uses Emacs.app when emacs is not on PATH" {
  stub rg
  printf '#!/bin/bash\n' >"$EMACS_APP_BIN"
  chmod +x "$EMACS_APP_BIN"
  section_doom >/dev/null 2>&1 || true
  [ "$EMACS" = "$EMACS_APP_BIN" ]
}

@test "section_doom: dry-run changes nothing" {
  DRY_RUN=1
  stub emacs
  stub rg
  run section_doom
  assert_contains "$output" "[dry-run] git clone --depth 1 https://github.com/doomemacs/doomemacs"
  assert_contains "$output" "[dry-run] $HOME/.config/emacs/bin/doom install --no-config --force"
  refute_called "git clone"
  [ ! -e "$HOME/.config/emacs" ]
  [ ! -e "$HOME/.config/doom" ]
}

# --- nvchad ---

@test "section_nvchad: fails without neovim" {
  run section_nvchad
  assert_contains "$output" "neovim not found"
  [ "$FAILED_ITEMS" = "" ] # run is a subshell; check via direct call
  section_nvchad 2>/dev/null || true
  [ "$FAILED_ITEMS" = "nvchad"$'\n' ]
}

@test "section_nvchad: links config if missing and syncs plugins" {
  stub nvim
  section_nvchad >/dev/null
  [ "$(readlink "$HOME/.config/nvim")" = "$REPO_ROOT/configs/nvim" ]
  assert_called "nvim --headless +Lazy! restore +qa"
}

@test "section_nvchad: keeps an existing config dir" {
  stub nvim
  mkdir -p "$HOME/.config/nvim"
  section_nvchad >/dev/null
  [ ! -L "$HOME/.config/nvim" ]
}

@test "section_nvchad: dry-run without neovim still prints the sync" {
  DRY_RUN=1
  run section_nvchad
  assert_contains "$output" "[dry-run] nvim --headless"
}

# --- macos ---

@test "section_macos: writes defaults and restarts Finder/Dock" {
  section_macos >/dev/null
  assert_called "defaults write NSGlobalDomain KeyRepeat -int 2"
  assert_called "defaults write com.apple.finder ShowPathbar -bool true"
  assert_called "defaults write com.apple.dock autohide -bool true"
  assert_called "defaults write com.apple.screencapture location -string $HOME/Pictures/Screenshots"
  assert_called "killall Finder"
  assert_called "killall Dock"
  [ -d "$HOME/Pictures/Screenshots" ]
}

@test "section_macos: dry-run calls nothing" {
  DRY_RUN=1
  run section_macos
  assert_contains "$output" "[dry-run] defaults write"
  refute_called "defaults"
  refute_called "killall"
}

@test "section_shell: stops when the oh-my-zsh installer fails" {
  stub curl 'echo "exit 1"'
  section_shell >/dev/null 2>&1 || true
  [ "$FAILED_ITEMS" = "oh-my-zsh"$'\n' ]
  refute_called "git clone"
  # so the next run retries the install
  [ ! -e "$HOME/.oh-my-zsh" ]
}

@test "section_doom: stops if ~/.config/emacs can't be backed up" {
  stub emacs
  stub rg
  mkdir -p "$HOME/.config/emacs"
  stub mv 'exit 1'
  section_doom >/dev/null 2>&1 || true
  assert_contains "$FAILED_ITEMS" "backup $HOME/.config/emacs"
  refute_called "git clone"
  refute_called "doom install"
}
