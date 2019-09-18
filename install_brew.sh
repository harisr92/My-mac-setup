url="https://raw.githubusercontent.com/Homebrew/install/master/install"
/usr/bin/ruby -e "$(curl -fsSL $url)"

# completion
echo "if type brew &>/dev/null; then; FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH; fi;" >> ~/.zshrc

