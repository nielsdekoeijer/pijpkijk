#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ip_address="10.251.225.48"

echo "1. Building pijpkijk..."
zig build

echo "2. Setting up secure socket directory..."
# -p /tmp ensures we avoid Nix's massive path lengths
SOCKET_DIR=$(mktemp -d -p /tmp pijpkijk.XXXXXX)
SOCKET_PATH="$SOCKET_DIR/pipewire-0"

cleanup() {
    echo -e "\nCleaning up SSH tunnel and temporary socket..."
    kill "$SSH_PID" 2>/dev/null || true
    rm -rf "$SOCKET_DIR"
}
trap cleanup EXIT

echo "3. Establishing SSH tunnel to root@$ip_address..."
ssh -nNT -L "$SOCKET_PATH:/run/pipewire/pipewire-0" "root@$ip_address" &
SSH_PID=$!

echo "4. Waiting for SSH handshake to complete..."
# 3 seconds guarantees SSH is fully authenticated before PipeWire knocks on the door
sleep 3 

echo "5. Launching pijpkijk..."
PIPEWIRE_RUNTIME_DIR="$SOCKET_DIR" ./zig-out/bin/pijpkijk
