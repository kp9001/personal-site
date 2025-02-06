#!/bin/bash

rm ./*.tar.gz
wget $( curl -L -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep "browser_download_url.*linux-amd64.tar.gz" | grep -v "extended" | cut -d\" -f4 )
#wget https://github.com/gohugoio/hugo/releases/download/v0.119.0/hugo_0.119.0_Linux-64bit.tar.gz
tar xvf ./*.tar.gz
chmod u+x ./hugo
./hugo --minify
