#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

scp -P 22220 nubuntu@localhost:err ./err
