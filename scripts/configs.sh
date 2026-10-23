# shellcheck shell=bash
# Section: configs (symlink dotfiles from configs/ into $HOME)

# link_target <source>: target path for a source from configs/links.txt
link_target() {
  awk -v s="$1" '!/^[[:space:]]*(#|$)/ && $1 == s { print $2 }' "$ROOT/configs/links.txt"
}

section_configs() {
  local src target
  for src in "$@"; do
    target=$(expand_home "$(link_target "$src")")
    [ -n "$target" ] || { warn "no target for $src in configs/links.txt"; continue; }
    backup_and_link "$ROOT/configs/$src" "$target"
  done
}
