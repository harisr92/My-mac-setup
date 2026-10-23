#!/bin/bash
# Security / health check for every package this repo installs.
#
# Fails on:  packages that don't exist, are disabled, are listed under an old or
#            aliased name, come from a tap not declared in cli/taps.txt, or (casks)
#            download over plain http; App Store ids that don't exist.
# Warns on:  deprecated packages and casks without a checksum (sha256 :no_check).
#
# Needs brew, jq and curl. Set MAC_SETUP_ROOT to check lists in another directory.
set -u

HERE=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${MAC_SETUP_ROOT:-$HERE}
# shellcheck source-path=SCRIPTDIR source=../lib/common.sh
. "$HERE/lib/common.sh"

ERRORS=0
WARNINGS=0

for tool in brew jq curl; do
  have "$tool" || die "$tool is required"
done

ALLOWED_TAPS="homebrew/core homebrew/cask $(list_names "$ROOT/cli/taps.txt" | tr '\n' ' ')"

# line_of <file> <name>: line number of an entry (for GitHub annotations)
line_of() {
  awk -v n="$2" '{ split($0, f, /[[:space:]]+/); if ((f[1] == "" ? f[2] : f[1]) == n) { print NR; exit } }' "$ROOT/$1"
}

# problem <error|warning> <file> <name> <message>
problem() {
  local level=$1 file=$2 name=$3 msg=$4
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::%s file=%s,line=%s::%s: %s\n' "$level" "$file" "$(line_of "$file" "$name")" "$name" "$msg"
  fi
  if [ "$level" = error ]; then
    ERRORS=$((ERRORS + 1))
    err "$file: $name: $msg"
  else
    WARNINGS=$((WARNINGS + 1))
    warn "$file: $name: $msg"
  fi
}

# check_common <file> <name> <canonical names> <tap> <deprecated> <disabled> <reason>
check_common() {
  local file=$1 name=$2 canonical=$3 tap=$4 deprecated=$5 disabled=$6 reason=$7
  in_words "$name" "$canonical" ||
    problem error "$file" "$name" "is now '${canonical%% *}'; list it under that name"
  in_words "$tap" "$ALLOWED_TAPS" ||
    problem error "$file" "$name" "comes from tap '$tap', which isn't in cli/taps.txt"
  [ "$disabled" = true ] && problem error "$file" "$name" "is disabled in Homebrew${reason:+ ($reason)}"
  [ "$deprecated" = true ] && problem warning "$file" "$name" "is deprecated in Homebrew${reason:+ ($reason)}"
  return 0
}

check_formula() {
  local name=$1 json short full tap deprecated disabled reason
  if ! json=$(brew info --json=v2 --formula "$name" 2>/dev/null); then
    problem error cli/formulae.txt "$name" "not found in Homebrew"
    return
  fi
  IFS='|' read -r short full tap deprecated disabled reason < <(printf '%s' "$json" | jq -r '
    .formulae[0] | [.name, .full_name, .tap, .deprecated, .disabled,
      (.disable_reason // .deprecation_reason // "")] | map(tostring) | join("|")')
  check_common cli/formulae.txt "$name" "$full $short" "$tap" "$deprecated" "$disabled" "$reason"
}

check_cask() {
  local name=$1 json token full tap deprecated disabled reason sha url
  if ! json=$(brew info --json=v2 --cask "$name" 2>/dev/null); then
    problem error gui/casks.txt "$name" "not found in Homebrew"
    return
  fi
  IFS='|' read -r token full tap deprecated disabled reason sha url < <(printf '%s' "$json" | jq -r '
    .casks[0] | [.token, .full_token, .tap, .deprecated, .disabled,
      (.disable_reason // .deprecation_reason // ""), .sha256, .url] | map(tostring) | join("|")')
  check_common gui/casks.txt "$name" "$token $full" "$tap" "$deprecated" "$disabled" "$reason"
  case "$url" in
    https://*) ;;
    *) problem error gui/casks.txt "$name" "downloads over an insecure URL: $url" ;;
  esac
  [ "$sha" = no_check ] && problem warning gui/casks.txt "$name" "has no checksum (sha256 :no_check), the download isn't verified"
  return 0
}

check_mas() {
  local id=$1 json count
  if ! json=$(curl -fsS --max-time 20 "https://itunes.apple.com/lookup?id=$id" 2>/dev/null); then
    problem warning gui/mas.txt "$id" "couldn't reach the App Store to check it"
    return
  fi
  count=$(printf '%s' "$json" | jq -r '.resultCount // 0')
  [ "$count" -gt 0 ] || problem error gui/mas.txt "$id" "no App Store app with this id"
}

header "Formulae (cli/formulae.txt)"
for name in $(list_names "$ROOT/cli/formulae.txt"); do check_formula "$name"; done

header "Casks (gui/casks.txt)"
for name in $(list_names "$ROOT/gui/casks.txt"); do check_cask "$name"; done

header "App Store (gui/mas.txt)"
for id in $(list_names "$ROOT/gui/mas.txt"); do check_mas "$id"; done

header "Result"
log "$ERRORS error(s), $WARNINGS warning(s)"
[ "$ERRORS" -eq 0 ]
