#
# Prompt character
#

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

SPACESHIP_CHAR_PREFIX="${SPACESHIP_CHAR_PREFIX=""}"
SPACESHIP_CHAR_SUFFIX="${SPACESHIP_CHAR_SUFFIX=""}"
SPACESHIP_CHAR_SYMBOL="${SPACESHIP_CHAR_SYMBOL="➜ "}"
SPACESHIP_CHAR_SYMBOL_ROOT="${SPACESHIP_CHAR_SYMBOL_ROOT="$SPACESHIP_CHAR_SYMBOL"}"
SPACESHIP_CHAR_SYMBOL_SECONDARY="${SPACESHIP_CHAR_SYMBOL_SECONDARY="$SPACESHIP_CHAR_SYMBOL"}"
SPACESHIP_CHAR_COLOR_SUCCESS="${SPACESHIP_CHAR_COLOR_SUCCESS="green"}"
SPACESHIP_CHAR_COLOR_FAILURE="${SPACESHIP_CHAR_COLOR_FAILURE="red"}"
SPACESHIP_CHAR_COLOR_SECONDARY="${SPACESHIP_CHAR_COLOR_SECONDARY="yellow"}"
SPACESHIP_CHAR_CHAR_SUCCESS="${SPACESHIP_CHAR_CHAR_SUCCESS="🥰  "}"
SPACESHIP_CHAR_CHAR_FAILURE="${SPACESHIP_CHAR_CHAR_FAILURE="😡 "}"

# ------------------------------------------------------------------------------
# Section
# ------------------------------------------------------------------------------

# Paint $PROMPT_SYMBOL in red if previous command was fail and
# paint in green if everything was OK.
spaceship_char() {
  local 'char'

  if [[ $RETVAL -eq 0 ]]; then
    char="$SPACESHIP_CHAR_CHAR_SUCCESS"
  else
    char="$SPACESHIP_CHAR_CHAR_FAILURE"
  fi

  spaceship::section \
    "$SPACESHIP_CHAR_PREFIX" \
    "$char" \
    "$SPACESHIP_CHAR_SUFFIX"
}
