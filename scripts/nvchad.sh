# shellcheck shell=bash
# Section: nvchad (NvChad is a lazy.nvim plugin of our config; this syncs plugins)

section_nvchad() {
  local nvim_dir="$HOME/.config/nvim"

  if ! have nvim && [ "$DRY_RUN" != 1 ]; then
    err "neovim not found; install it with: ./setup.sh --only cli:neovim"
    mark_failed "nvchad"
    return 0
  fi
  [ -e "$nvim_dir" ] || backup_and_link "$ROOT/configs/nvim" "$nvim_dir"
  track "NvChad plugins (Lazy sync)" nvim --headless "+Lazy! restore" +qa
}
