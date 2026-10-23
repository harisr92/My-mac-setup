#!/usr/bin/env bats
# Static checks: syntax, lint and the data files

load test_helper

scripts() {
  printf '%s\n' "$REPO_ROOT/setup.sh" "$REPO_ROOT/bootstrap.sh" "$REPO_ROOT/lib/common.sh" "$REPO_ROOT"/scripts/*.sh
}

@test "all scripts parse with macOS stock bash 3.2" {
  while read -r f; do
    /bin/bash -n "$f"
  done < <(scripts)
}

@test "all scripts pass shellcheck" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  run shellcheck -x -s bash $(scripts)
  assert_status 0
}

@test "entry points are executable" {
  [ -x "$REPO_ROOT/setup.sh" ]
  [ -x "$REPO_ROOT/bootstrap.sh" ]
}

@test "zshrc parses" {
  command -v zsh >/dev/null || skip "zsh not installed"
  zsh -n "$REPO_ROOT/configs/zsh/zshrc"
}

no_duplicates() {
  local dupes
  dupes=$(. "$REPO_ROOT/lib/common.sh" && list_names "$REPO_ROOT/$1" | sort | uniq -d)
  [ -z "$dupes" ] || { echo "duplicates in $1: $dupes"; return 1; }
}

@test "lists have no duplicate entries" {
  no_duplicates cli/formulae.txt
  no_duplicates cli/taps.txt
  no_duplicates gui/casks.txt
  no_duplicates gui/mas.txt
}

@test "App Store entries are numeric ids with a name" {
  run bash -c ". '$REPO_ROOT/lib/common.sh' && read_list '$REPO_ROOT/gui/mas.txt'"
  [ "${#lines[@]}" -gt 0 ]
  for line in "${lines[@]}"; do
    [[ "${line%%$'\t'*}" =~ ^[0-9]+$ ]] || { echo "bad id: $line"; return 1; }
    [ -n "${line#*$'\t'}" ] || { echo "missing name: $line"; return 1; }
  done
}

@test "every tapped formula's tap is in cli/taps.txt" {
  taps=$(. "$REPO_ROOT/lib/common.sh" && list_names "$REPO_ROOT/cli/taps.txt" | tr '\n' ' ')
  while read -r name; do
    case "$name" in */*/*)
      tap=${name%/*}
      [[ " $taps " == *" $tap "* ]] || { echo "$tap (for $name) missing from taps.txt"; return 1; }
      ;;
    esac
  done < <(. "$REPO_ROOT/lib/common.sh" && list_names "$REPO_ROOT/cli/formulae.txt")
}

@test "every configs/links.txt source exists and targets are under ~" {
  while read -r src target; do
    [ -e "$REPO_ROOT/configs/$src" ] || { echo "missing configs/$src"; return 1; }
    [[ "$target" == "~/"* ]] || { echo "target not under ~: $target"; return 1; }
  done < <(grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/configs/links.txt")
}

@test "every file in configs/ is linked" {
  linked=$(grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/configs/links.txt" | awk '{ print $1 }')
  for f in $(cd "$REPO_ROOT/configs" && find . -type f ! -name links.txt | sed 's|^\./||'); do
    ok=0
    for l in $linked; do
      case "$f" in "$l" | "$l"/*) ok=1 ;; esac
    done
    [ "$ok" = 1 ] || { echo "configs/$f is not linked anywhere"; return 1; }
  done
}

@test "no secrets in tracked files" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  run gitleaks dir "$REPO_ROOT" --no-banner
  assert_status 0
}
