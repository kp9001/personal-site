#!/bin/bash

set -eou pipefail

wget $( curl -L -s https://api.github.com/repos/gohugoio/hugo/releases/latest | grep "browser_download_url.*linux-amd64.tar.gz" | grep -v "extended" | cut -d\" -f4 )
tar xvf ./*.tar.gz
chmod u+x ./hugo

./hugo --minify
