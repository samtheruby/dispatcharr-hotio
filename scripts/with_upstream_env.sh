#!/bin/bash
set -euo pipefail

# Apply application defaults after Hotio initializes its own services.
while IFS= read -r -d '' setting; do
    name=${setting%%=*}
    if [[ ! -v "$name" ]]; then
        export "${setting?}"
    fi
done < /usr/local/share/dispatcharr-upstream/environment

export PATH="/dispatcharrpy/bin:$PATH"
exec "$@"
