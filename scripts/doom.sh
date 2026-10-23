# shellcheck shell=bash
# Section: doom (Doom Emacs framework; config itself is linked by the configs section)

section_doom() {
  local emacs_dir="$HOME/.config/emacs" doom_dir="$HOME/.config/doom"

  have git || { err "git is required for Doom Emacs"; mark_failed "doom"; return 0; }
  if ! have emacs; then
    if [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ]; then
      export EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
    else
      warn "Emacs not found; install it with: ./setup.sh --only gui:emacs"
    fi
  fi
  have rg || warn "ripgrep not found; Doom needs it (./setup.sh --only cli:ripgrep)"

  # Doom must see our config, not generate its own
  [ -e "$doom_dir" ] || backup_and_link "$ROOT/configs/doom" "$doom_dir"

  if [ -x "$emacs_dir/bin/doom" ]; then
    mark_skipped "doomemacs clone" "already installed"
    track "doom sync" "$emacs_dir/bin/doom" sync
  else
    if [ -e "$emacs_dir" ]; then
      run mkdir -p "$BACKUP_DIR/.config" && run mv "$emacs_dir" "$BACKUP_DIR/.config/emacs"
    fi
    git_clone https://github.com/doomemacs/doomemacs "$emacs_dir"
    track "doom install" "$emacs_dir/bin/doom" install --no-config --force
  fi
}
