#!/bin/bash
set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT

# A different OS must fail before any upstream runtime packages are installed.
if UPSTREAM_IMAGE=$(jq -r .upstream_image meta.json) \
   VERSION=$(jq -r .version meta.json) \
   docker buildx bake app --set app.target=dependencies \
     --set app.args.HOTIO_BASE_IMAGE=debian:13-slim --progress=plain >"$log" 2>&1; then
    echo 'FAIL: incompatible upstream runtime was accepted' >&2
    exit 1
fi
if ! grep -qF 'Incompatible upstream runtime:' "$log"; then
    tail -n 40 "$log"
    echo 'FAIL: build failed before reaching the compatibility check' >&2
    exit 1
fi
echo 'PASS: incompatible OS blocks packaging'
