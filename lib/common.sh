# shellcheck shell=bash
# Shared helpers. Must stay compatible with macOS stock bash 3.2.

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}
# Terminal used for prompts (overridable for tests)
TTY_IN=${MAC_SETUP_TTY_IN:-/dev/tty}
TTY_OUT=${MAC_SETUP_TTY_OUT:-/dev/tty}
BACKUP_DIR="$HOME/.mac-setup-backup/$(date +%Y%m%d-%H%M%S)"

# Summary buckets, newline separated
DONE_ITEMS=""
SKIPPED_ITEMS=""
FAILED_ITEMS=""

if [ -t 1 ]; then
  C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_DIM=$'\033[2m' C_RESET=$'\033[0m'
else
  C_BLUE="" C_GREEN="" C_YELLOW="" C_RED="" C_DIM="" C_RESET=""
fi

header() { printf '\n%s==> %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
log()    { printf '%s\n' "$*"; }
ok()     { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()   { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()    { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()    { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

has_tty() { [ -r "$TTY_IN" ] && [ -w "$TTY_OUT" ] && (exec <"$TTY_IN") 2>/dev/null; }

# run_cmd <cmd> [args...]: the only way mutating commands are executed.
# In dry-run mode the command is printed instead.
run_cmd() {
  if [ "$1" = run_sh ]; then
    shift
    run_sh "$@"
    return
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s[dry-run]%s' "$C_DIM" "$C_RESET"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# Same as run_cmd, but for a shell snippet (pipes, redirects, env assignments).
run_sh() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$1"
    return 0
  fi
  bash -c "$1"
}

mark_done() {
  DONE_ITEMS="$DONE_ITEMS$1"$'\n'
  [ "$DRY_RUN" = 1 ] || ok "$1"
}
mark_skipped() { SKIPPED_ITEMS="$SKIPPED_ITEMS$1"$'\n'; log "${C_DIM}- $1 (${2:-already done})${C_RESET}"; }
mark_failed()  { FAILED_ITEMS="$FAILED_ITEMS$1"$'\n'; err "$1 failed"; }

# track <label> <cmd> [args...]: run_cmd a command and record the outcome.
track() {
  local label=$1
  shift
  if run_cmd "$@"; then
    mark_done "$label"
  else
    mark_failed "$label"
    return 1
  fi
}

# read_list <file>: print "name<TAB>description" for each entry,
# skipping blank lines and comments. The description is the trailing "# ...".
read_list() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      line = $0; desc = ""
      i = index(line, "#")
      if (i > 0) { desc = substr(line, i + 1); line = substr(line, 1, i - 1) }
      sub(/^[[:space:]]+/, "", desc)
      split(line, f, /[[:space:]]+/)
      name = (f[1] == "" ? f[2] : f[1])
      print name "\t" desc
    }' "$1"
}

# list_names <file>: just the names from read_list.
list_names() { read_list "$1" | cut -f1; }

# in_words <word> <space separated list>
in_words() {
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

# choose <title>: reads "name<TAB>desc" lines on stdin, lets the user pick,
# prints the chosen names (one per line). Default (no input / no tty) is all.
choose() {
  local title=$1 items count reply names chosen n i
  items=$(cat)
  [ -z "$items" ] && return 0

  if [ "$ASSUME_YES" = 1 ] || ! has_tty; then
    printf '%s\n' "$items" | cut -f1
    return 0
  fi

  if have fzf; then
    reply=$(printf '%s\n' "$items" |
      awk -F'\t' '{ printf "%-32s %s\n", $1, $2 }' |
      fzf --multi --height=80% --layout=reverse --border \
        --prompt="$title> " \
        --header='All selected. TAB: toggle  ctrl-a: all  ctrl-d: none  ENTER: confirm  ESC: skip' \
        --bind 'start:select-all,ctrl-a:select-all,ctrl-d:deselect-all')
    printf '%s\n' "$reply" | awk 'NF { print $1 }'
    return 0
  fi

  names=$(printf '%s\n' "$items" | cut -f1)
  count=$(printf '%s\n' "$items" | wc -l | tr -d ' ')
  {
    printf '\n%s%s%s\n' "$C_BLUE" "$title" "$C_RESET"
    printf '%s\n' "$items" | awk -F'\t' '{ printf "  %3d) %-30s %s\n", NR, $1, $2 }'
    printf 'Select [Enter = all, n = none, e.g. "1 3 5-8"]: '
  } >"$TTY_OUT"
  read -r reply <"$TTY_IN" || reply=""

  case "$reply" in
    "" | a | all | A) printf '%s\n' "$names"; return 0 ;;
    n | none | N) return 0 ;;
  esac

  chosen=""
  for n in $(printf '%s' "$reply" | tr ',' ' '); do
    case "$n" in
      *-*)
        i=${n%-*}
        while [ "$i" -le "${n#*-}" ] 2>/dev/null; do chosen="$chosen $i"; i=$((i + 1)); done
        ;;
      *[!0-9]*) warn "ignoring '$n'" ;;
      *) chosen="$chosen $n" ;;
    esac
  done
  for i in $chosen; do
    [ "$i" -ge 1 ] && [ "$i" -le "$count" ] && printf '%s\n' "$names" | sed -n "${i}p"
  done
}

# confirm <question>: yes/no prompt, defaults to yes.
confirm() {
  local reply
  [ "$ASSUME_YES" = 1 ] && return 0
  has_tty || return 0
  printf '%s [Y/n] ' "$1" >"$TTY_OUT"
  read -r reply <"$TTY_IN" || reply=""
  case "$reply" in n | N | no | No) return 1 ;; esac
  return 0
}

# shellcheck disable=SC2088
expand_home() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# backup_and_link <source> <target>: symlink target -> source, moving any
# existing file/dir at target into $BACKUP_DIR first.
backup_and_link() {
  local src=$1 target=$2 rel
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
    mark_skipped "link $target" "already linked"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    rel=${target#"$HOME"/}
    if ! { run_cmd mkdir -p "$(dirname "$BACKUP_DIR/$rel")" && run_cmd mv "$target" "$BACKUP_DIR/$rel"; }; then
      mark_failed "backup $target"
      return 1
    fi
  fi
  [ -d "$(dirname "$target")" ] || run_cmd mkdir -p "$(dirname "$target")"
  track "link $target -> $src" ln -s "$src" "$target"
}

# git_clone <repo> <dest>: shallow clone unless dest already exists.
git_clone() {
  if [ -d "$2" ]; then
    mark_skipped "clone $2" "already exists"
  else
    track "clone $1" git clone --depth 1 "$1" "$2"
  fi
}

print_summary() {
  header "Summary$([ "$DRY_RUN" = 1 ] && printf ' (dry run, nothing was changed)')"
  local n_done n_skip n_fail
  n_done=$(printf '%s' "$DONE_ITEMS" | grep -c . || true)
  n_skip=$(printf '%s' "$SKIPPED_ITEMS" | grep -c . || true)
  n_fail=$(printf '%s' "$FAILED_ITEMS" | grep -c . || true)
  local verb="done"
  [ "$DRY_RUN" = 1 ] && verb="would be done"
  log "${C_GREEN}$n_done $verb${C_RESET}, $n_skip skipped, ${C_RED}$n_fail failed${C_RESET}"
  if [ "$n_fail" -gt 0 ]; then
    log "Failed:"
    printf '%s' "$FAILED_ITEMS" | sed 's/^/  - /'
  fi
  if [ -d "$BACKUP_DIR" ]; then
    log "Previous configs were backed up to $BACKUP_DIR"
  fi
}
