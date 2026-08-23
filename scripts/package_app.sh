#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
cd "$root_dir"
make package
