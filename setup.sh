#!/bin/bash
# shellcheck disable=SC2034  # ASSUME_YES/DRY_RUN are read in lib/common.sh
# One-command Mac setup. Run ./setup.sh --help for usage.
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
. "$ROOT/lib/common.sh"
for f in "$ROOT"/scripts/*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

SECTIONS="brew cli gui mas shell configs doom nvchad macos"

section_desc() {
  case "$1" in
    brew) echo "Homebrew package manager" ;;
    cli) echo "Command line tools (cli/formulae.txt)" ;;
    gui) echo "GUI apps and fonts (gui/casks.txt)" ;;
    mas) echo "Mac App Store apps (gui/mas.txt, needs sign-in)" ;;
    shell) echo "oh-my-zsh, spaceship prompt, zsh plugins" ;;
    configs) echo "Symlink dotfiles (configs/links.txt)" ;;
    doom) echo "Doom Emacs install + sync" ;;
    nvchad) echo "NvChad / Neovim plugin sync" ;;
    macos) echo "macOS defaults (Finder, Dock, keyboard)" ;;
  esac
}

# section_items <section>: "name<TAB>desc" lines for sections that have item lists
section_items() {
  case "$1" in
    cli) read_list "$ROOT/cli/formulae.txt" ;;
    gui) read_list "$ROOT/gui/casks.txt" ;;
    mas) read_list "$ROOT/gui/mas.txt" ;;
    configs) awk '!/^[[:space:]]*(#|$)/ { print $1 "\t" $2 }' "$ROOT/configs/links.txt" ;;
  esac
}

has_items() { case "$1" in cli | gui | mas | configs) return 0 ;; esac; return 1; }

usage() {
  cat <<EOF
Usage: ./setup.sh [options]

With no options you get an interactive menu: pick sections, then pick items.

Options:
  -a, --all                 Install everything, no prompts
  -o, --only SPEC           Only these sections/items (repeatable). SPEC is
                            "section", "section1,section2" or "section:item1,item2"
  -n, --dry-run             Print what would be done without changing anything
  -l, --list [SECTION]      List sections, or the items of one section
  -y, --yes                 Accept defaults in prompts (everything selected)
  -h, --help                Show this help

Sections (run in this order):
EOF
  for s in $SECTIONS; do printf '  %-9s %s\n' "$s" "$(section_desc "$s")"; done
  cat <<EOF

Examples:
  ./setup.sh --dry-run --all
  ./setup.sh --only gui:firefox,spotify --only cli:neovim,ripgrep
  ./setup.sh --only configs,doom,nvchad
EOF
}

valid_section() { in_words "$1" "$SECTIONS"; }

# Selection per section is stored in SEL_<section>:
#   unset/empty = skip, "*" = all items, otherwise space separated item names
select_section() {
  local s=$1 items=${2:-} cur
  valid_section "$s" || die "unknown section '$s' (see --list)"
  cur=$(eval "printf '%s' \"\${SEL_$s:-}\"")
  if [ -z "$items" ] || [ "$cur" = "*" ]; then
    items="*"
  else
    items="$cur $(printf '%s' "$items" | tr ',' ' ')"
  fi
  eval "SEL_$s=\$items"
}

get_selection() { eval "printf '%s' \"\${SEL_$1:-}\""; }

parse_only() {
  local spec=$1 part
  case "$spec" in
    *:*) select_section "${spec%%:*}" "${spec#*:}" ;;
    *) for part in $(printf '%s' "$spec" | tr ',' ' '); do select_section "$part"; done ;;
  esac
}

list_cmd() {
  if [ -z "${1:-}" ]; then
    for s in $SECTIONS; do printf '%-9s %s\n' "$s" "$(section_desc "$s")"; done
  elif has_items "$1"; then
    section_items "$1" | awk -F'\t' '{ printf "%-32s %s\n", $1, $2 }'
  elif valid_section "$1"; then
    echo "'$1' has no individual items"
  else
    die "unknown section '$1'"
  fi
}

ALL=0
ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -a | --all) ALL=1 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    -o | --only)
      [ $# -ge 2 ] || die "--only needs a value"
      parse_only "$2"
      ONLY=1
      shift
      ;;
    --only=*) parse_only "${1#--only=}"; ONLY=1 ;;
    -l | --list) list_cmd "${2:-}"; exit 0 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option '$1'" ;;
  esac
  shift
done

if [ "$ALL" = 1 ]; then
  ASSUME_YES=1
  for s in $SECTIONS; do select_section "$s"; done
elif [ "$ONLY" = 0 ]; then
  menu=$(for name in $SECTIONS; do printf '%s\t%s\n' "$name" "$(section_desc "$name")"; done)
  for s in $(printf '%s\n' "$menu" | choose "Sections"); do
    select_section "$s"
  done
  # Narrow down item lists interactively
  for s in $SECTIONS; do
    if [ "$(get_selection "$s")" != "*" ] || ! has_items "$s"; then continue; fi
    picked=$(section_items "$s" | choose "$s" | tr '\n' ' ')
    if [ -z "${picked// /}" ]; then eval "SEL_$s="; else eval "SEL_$s=\$picked"; fi
  done
fi

# Resolve "*" to the full item list and drop unknown names
resolve_items() {
  local s=$1 sel all name
  sel=$(get_selection "$s")
  all=$(section_items "$s" | cut -f1 | tr '\n' ' ')
  if [ "$sel" = "*" ]; then
    printf '%s' "$all"
    return
  fi
  for name in $sel; do
    if in_words "$name" "$all"; then printf '%s ' "$name"; else warn "'$name' is not in the $s list, skipping"; fi
  done
}

PLAN=""
for s in $SECTIONS; do
  [ -n "$(get_selection "$s")" ] && PLAN="$PLAN $s"
done
[ -n "$PLAN" ] || die "nothing selected"

header "Mac setup$([ "$DRY_RUN" = 1 ] && printf ' (DRY RUN)')"
log "Sections:$PLAN"

if [ "$DRY_RUN" = 0 ]; then
  confirm "Continue?" || exit 0
  # Cache sudo for Homebrew/cask installs and keep it alive
  if in_words brew "$PLAN" || in_words gui "$PLAN" || in_words cli "$PLAN"; then
    if sudo -v; then
      while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done >/dev/null 2>&1 3>&- &
      SUDO_KEEPALIVE=$!
      trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT
    fi
  fi
fi

for s in $PLAN; do
  header "$s: $(section_desc "$s")"
  if has_items "$s"; then
    items=$(resolve_items "$s")
    if [ -z "${items// /}" ]; then
      log "nothing to do"
      continue
    fi
    # shellcheck disable=SC2086
    "section_$s" $items
  else
    "section_$s"
  fi
  # Pick up a freshly installed Homebrew for later sections
  [ "$s" = brew ] && { have brew || load_brew_env; }
done

print_summary
[ "$DRY_RUN" = 1 ] || log "Open a new terminal to load the new shell config."
