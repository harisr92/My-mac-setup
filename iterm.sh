url="https://iterm2.com/downloads/stable/latest"
outfile=iterm.zip

echo "Downloading iterm2"
curl $url -o $outfile
tar -xvf $outfile
mv iTerm.app ~/Applications
