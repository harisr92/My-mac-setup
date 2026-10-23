# shellcheck shell=bash
# Sections: brew (Homebrew itself), cli (formulae), gui (casks), mas (App Store)

load_brew_env() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then
      eval "$("$b" shellenv)"
      return 0
    fi
  done
  return 1
}

section_brew() {
  if have brew || load_brew_env; then
    mark_skipped "Homebrew" "already installed"
  else
    # shellcheck disable=SC2016
    track "Homebrew" run_sh 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    [ "$DRY_RUN" = 1 ] || load_brew_env || die "Homebrew install failed"
  fi
}

require_brew() {
  have brew || load_brew_env && return 0
  if [ "$DRY_RUN" = 1 ]; then
    warn "Homebrew not installed; showing what would be installed"
    return 0
  fi
  err "Homebrew is not installed. Run with --only brew first."
  return 1
}

# brew_installed <--formula|--cask>: names of installed packages
brew_installed() { have brew && brew list "$1" -1 2>/dev/null; }

brew_install() {
  local kind=$1 installed=$2 name
  shift 2
  for name in "$@"; do
    if in_words "${name##*/}" "$installed"; then
      mark_skipped "$name"
    else
      track "$name" brew install "$kind" "$name"
    fi
  done
}

section_cli() {
  require_brew || return 0
  local tap taps
  taps=$(have brew && brew tap 2>/dev/null | tr '\n' ' ')
  for tap in $(list_names "$ROOT/cli/taps.txt"); do
    if in_words "$tap" "$taps"; then mark_skipped "tap $tap"; else track "tap $tap" brew tap "$tap"; fi
  done
  brew_install --formula "$(brew_installed --formula | tr '\n' ' ')" "$@"
}

section_gui() {
  require_brew || return 0
  brew_install --cask "$(brew_installed --cask | tr '\n' ' ')" "$@"
}

section_mas() {
  require_brew || return 0
  if ! have mas; then
    if [ "$DRY_RUN" = 1 ]; then
      warn "mas not installed yet (it's in cli/formulae.txt)"
    else
      track "mas" brew install mas || return 0
    fi
  fi
  warn "App Store installs need you to be signed in to the App Store app"
  local installed id
  installed=$(have mas && mas list 2>/dev/null | awk '{ print $1 }' | tr '\n' ' ')
  for id in "$@"; do
    if in_words "$id" "$installed"; then
      mark_skipped "app store $id"
    else
      track "app store $id ($(read_list "$ROOT/gui/mas.txt" | awk -F'\t' -v id="$id" '$1 == id { print $2 }'))" mas install "$id"
    fi
  done
}
