#!/bin/bash
set -e

cd "$(dirname "$0")/../tailscale-daemon"

echo "Building chill-tailscale for all platforms..."

mkdir -p ../build

# Linux amd64
echo "  -> Linux amd64..."
GOOS=linux GOARCH=amd64 go build -o ../build/chill-tailscale-linux-amd64 .

# Windows amd64
echo "  -> Windows amd64..."
GOOS=windows GOARCH=amd64 go build -o ../build/chill-tailscale-windows-amd64.exe .

# macOS Intel
echo "  -> macOS amd64..."
GOOS=darwin GOARCH=amd64 go build -o ../build/chill-tailscale-darwin-amd64 .

# macOS Apple Silicon
echo "  -> macOS arm64..."
GOOS=darwin GOARCH=arm64 go build -o ../build/chill-tailscale-darwin-arm64 .

echo "Done! Binaries in build/"
