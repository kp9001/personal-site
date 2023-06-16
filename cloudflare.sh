#!/bin/bash

rm ./*.tar.gz
wget $( curl -L -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep "browser_download_url.*extended.*linux-amd64.tar.gz" | cut -d\" -f4 )
tar xvf ./*.tar.gz
chmod u+x ./hugo
./hugo --minify
