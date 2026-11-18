#!/bin/bash
set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# The Noble adaptation must reject a different OS before compiling anything.
if docker buildx bake ffmpeg --set ffmpeg.target=builder \
    --set ffmpeg.args.UBUNTU_BASE=debian:13-slim --progress=plain >"$log" 2>&1; then
    echo 'FAIL: unsupported build OS was accepted' >&2
    exit 1
fi
if ! grep -qF 'Unsupported Hotio base:' "$log"; then
    tail -n 40 "$log"
    echo 'FAIL: build failed before reaching the compatibility check' >&2
    exit 1
fi
echo 'PASS: unsupported OS blocks runtime building'
