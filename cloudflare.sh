#!/bin/bash

rm ./*.tar.gz 2>/dev/null

wget $( curl -L -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep "browser_download_url.*linux-amd64.tar.gz" | grep -v "extended" | cut -d\" -f4 )
tar -xvzf ./*.tar.gz hugo
chmod u+x ./hugo

./hugo --minify
