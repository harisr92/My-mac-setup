# My Mac setup

One command to set up a new Mac: Homebrew, CLI tools, GUI apps, dotfiles, Doom Emacs and NvChad.

## Fresh Mac

```sh
curl -fsSL https://raw.githubusercontent.com/harisr92/My-mac-setup/master/bootstrap.sh | bash
```

This installs the Xcode Command Line Tools, clones the repo to `~/dev/My-mac-setup`
and starts `setup.sh` with an interactive menu. Options are passed through:

```sh
curl -fsSL https://raw.githubusercontent.com/harisr92/My-mac-setup/master/bootstrap.sh | bash -s -- --dry-run --all
```

## Usage

```sh
./setup.sh                                  # interactive: pick sections, then items
./setup.sh --all                            # everything, no prompts
./setup.sh --dry-run --all                  # show what would happen, change nothing
./setup.sh --only gui                       # one section
./setup.sh --only gui:firefox,spotify       # specific apps
./setup.sh --only cli:neovim --only configs,doom,nvchad
./setup.sh --list                           # list sections
./setup.sh --list gui                       # list items in a section
```

In the interactive menu, item lists open in `fzf` (everything pre-selected; TAB toggles,
ctrl-d clears, ctrl-a selects all). Without fzf you get a numbered menu: Enter for all,
`n` for none, or numbers and ranges like `1 3 5-8`.

Everything is idempotent: installed packages, existing clones and correct symlinks are skipped,
so it's safe to re-run.

## Sections

| Section   | What it does                                       | Edit                 |
|-----------|----------------------------------------------------|----------------------|
| `brew`    | Installs Homebrew                                  |                      |
| `cli`     | Taps + command line tools                          | `cli/taps.txt`, `cli/formulae.txt` |
| `gui`     | GUI apps and fonts (casks)                         | `gui/casks.txt`      |
| `mas`     | Mac App Store apps (sign in to the App Store first) | `gui/mas.txt`       |
| `shell`   | oh-my-zsh, spaceship prompt, zsh plugins           | `scripts/shell.sh`   |
| `configs` | Symlinks dotfiles into `$HOME`                     | `configs/links.txt`  |
| `doom`    | Clones Doom Emacs into `~/.config/emacs`, runs `doom install`/`doom sync` | `configs/doom/` |
| `nvchad`  | Syncs NvChad/Neovim plugins from `lazy-lock.json`  | `configs/nvim/`      |
| `macos`   | `defaults write` tweaks (keyboard, Finder, Dock, screenshots) | `scripts/macos.sh` |

## Layout

```
bootstrap.sh        curl | bash entry point
setup.sh            main script
lib/common.sh       helpers: dry-run aware run(), menus, symlinking
cli/                Homebrew taps and formulae
gui/                Homebrew casks and App Store apps
configs/            dotfiles (zsh, git, doom, nvim) + links.txt
scripts/            one file per section
```

## Adding things

- **CLI tool**: add a line to `cli/formulae.txt`, e.g. `httpie   # HTTP client`
- **GUI app**: find the cask with `brew search --cask <name>`, add it to `gui/casks.txt`
- **App Store app**: `mas search <name>`, add `<id>   # Name` to `gui/mas.txt`
- **Dotfile**: copy it into `configs/<dir>/` and add `<dir>/<file>   ~/target` to `configs/links.txt`

## Notes

- Configs are **symlinked**, so editing `~/.zshrc`, `~/.config/doom`, `~/.config/nvim` edits this repo.
  Anything that was already at a target is moved to `~/.mac-setup-backup/<timestamp>/` first.
- Machine-specific settings go in `~/.zshrc.local` and `~/.gitconfig.local` (not tracked).
- Not available through Homebrew, install by hand: DaVinci Resolve.
