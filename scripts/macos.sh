# shellcheck shell=bash
# Section: macos (system preferences via `defaults`)

section_macos() {
  # Keyboard: fast key repeat, no press-and-hold accent popup
  run_cmd defaults write NSGlobalDomain KeyRepeat -int 2
  run_cmd defaults write NSGlobalDomain InitialKeyRepeat -int 15
  run_cmd defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

  # Finder: show extensions, hidden files, path bar, status bar
  run_cmd defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  run_cmd defaults write com.apple.finder AppleShowAllFiles -bool true
  run_cmd defaults write com.apple.finder ShowPathbar -bool true
  run_cmd defaults write com.apple.finder ShowStatusBar -bool true
  run_cmd defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
  run_cmd defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Dock: auto-hide, no recent apps
  run_cmd defaults write com.apple.dock autohide -bool true
  run_cmd defaults write com.apple.dock show-recents -bool false

  # Screenshots into ~/Pictures/Screenshots
  run_cmd mkdir -p "$HOME/Pictures/Screenshots"
  run_cmd defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"

  run_cmd killall Finder
  run_cmd killall Dock
  run_cmd killall SystemUIServer
  mark_done "macOS defaults (some need a logout to apply)"
}
