#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ip_address="192.168.1.52"

zig build # -Doptimize=ReleaseFast

SOCKET_DIR=$(mktemp -d -p /tmp pijpkijk.XXXXXX)
SOCKET_PATH="$SOCKET_DIR/pipewire-0"

cleanup() {
    kill "$SSH_PID" 2>/dev/null || true
    rm -rf "$SOCKET_DIR"
}
trap cleanup EXIT

ssh -nNT -L "$SOCKET_PATH:/run/pipewire/pipewire-0" "root@$ip_address" &
SSH_PID=$!

PIPEWIRE_RUNTIME_DIR="$SOCKET_DIR" ./zig-out/bin/pijpkijk
