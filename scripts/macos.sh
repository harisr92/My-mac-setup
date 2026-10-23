# shellcheck shell=bash
# Section: macos (system preferences via `defaults`)

section_macos() {
  # Keyboard: fast key repeat, no press-and-hold accent popup
  run defaults write NSGlobalDomain KeyRepeat -int 2
  run defaults write NSGlobalDomain InitialKeyRepeat -int 15
  run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

  # Finder: show extensions, hidden files, path bar, status bar
  run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  run defaults write com.apple.finder AppleShowAllFiles -bool true
  run defaults write com.apple.finder ShowPathbar -bool true
  run defaults write com.apple.finder ShowStatusBar -bool true
  run defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
  run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Dock: auto-hide, no recent apps
  run defaults write com.apple.dock autohide -bool true
  run defaults write com.apple.dock show-recents -bool false

  # Screenshots into ~/Pictures/Screenshots
  run mkdir -p "$HOME/Pictures/Screenshots"
  run defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"

  run killall Finder
  run killall Dock
  run killall SystemUIServer
  mark_done "macOS defaults (some need a logout to apply)"
}
