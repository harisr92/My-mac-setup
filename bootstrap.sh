#!/bin/bash
# Fresh-Mac entry point:
#   curl -fsSL https://raw.githubusercontent.com/harisr92/My-mac-setup/master/bootstrap.sh | bash -s -- [setup.sh options]
# Installs the Xcode Command Line Tools (for git), clones this repo and runs setup.sh.
set -eu

REPO_URL=${MAC_SETUP_REPO:-https://github.com/harisr92/My-mac-setup.git}
DEST=${MAC_SETUP_DIR:-$HOME/dev/My-mac-setup}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in -n | --dry-run) DRY_RUN=1 ;; esac
done

if ! xcode-select -p >/dev/null 2>&1; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] xcode-select --install"
  else
    echo "==> Installing Xcode Command Line Tools (accept the dialog)..."
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
fi

if [ -d "$DEST/.git" ]; then
  echo "==> Updating $DEST"
  git -C "$DEST" pull --ff-only || echo "! could not update $DEST, using it as is"
elif [ "$DRY_RUN" = 1 ] && ! command -v git >/dev/null 2>&1; then
  echo "[dry-run] git clone $REPO_URL $DEST"
  echo "git is not available yet, so the rest of the dry run can't be shown."
  exit 0
else
  # Dry runs still need the lists, so clone into a temp dir instead of $DEST
  [ "$DRY_RUN" = 1 ] && DEST=$(mktemp -d)/My-mac-setup
  echo "==> Cloning $REPO_URL into $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
fi

# Reattach stdin to the terminal so prompts work under `curl | bash`
if [ -r /dev/tty ] && (exec </dev/tty) 2>/dev/null; then
  exec "$DEST/setup.sh" "$@" </dev/tty
else
  exec "$DEST/setup.sh" "$@"
fi
