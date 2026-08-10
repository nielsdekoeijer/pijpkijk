#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

zig build

cp ./zig-out/bin/pijpkijk /tmp/pijpkijk-deploy
strip /tmp/pijpkijk-deploy

patchelf \
  --set-interpreter /lib64/ld-linux-x86-64.so.2 \
  --set-rpath "/usr/lib/x86_64-linux-gnu:/usr/lib:/lib" \
  /tmp/pijpkijk-deploy

scp -P 22220 /tmp/pijpkijk-deploy nubuntu@localhost:pijpkijk
