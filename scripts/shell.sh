# shellcheck shell=bash
# Section: shell (oh-my-zsh, spaceship theme, zsh plugins)

section_shell() {
  local custom="$HOME/.oh-my-zsh/custom"

  if [ -d "$HOME/.oh-my-zsh" ]; then
    mark_skipped "oh-my-zsh"
  else
    # KEEP_ZSHRC: our zshrc comes from the configs section
    # shellcheck disable=SC2016
    track "oh-my-zsh" run_sh 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
  fi

  git_clone https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions"
  git_clone https://github.com/zsh-users/zsh-syntax-highlighting "$custom/plugins/zsh-syntax-highlighting"
  git_clone https://github.com/spaceship-prompt/spaceship-prompt "$custom/themes/spaceship-prompt"
  if [ -L "$custom/themes/spaceship.zsh-theme" ]; then
    mark_skipped "spaceship theme link"
  else
    track "spaceship theme link" ln -sf "$custom/themes/spaceship-prompt/spaceship.zsh-theme" "$custom/themes/spaceship.zsh-theme"
  fi

  if [ "${SHELL:-}" != "/bin/zsh" ]; then
    track "default shell zsh" chsh -s /bin/zsh
  fi
}
