#!/bin/bash
set -euo pipefail

image=${1:-dispatcharr-hotio:test}
upstream=${2:-}

if [[ -n "$upstream" ]]; then
    # Source builds change binary hashes; keep the release's media source pins.
    for notice in SOURCE_REVISION versions.env.ffmpeg intel-media.env; do
        test "$(docker run --rm --entrypoint sha256sum "$image" "/usr/local/share/doc/dispatcharr-ffmpeg/$notice")" \
            = "$(docker run --rm --entrypoint sha256sum "$upstream" "/usr/local/share/doc/dispatcharr-ffmpeg/$notice")"
    done
    manifest='cd /app; find . -type f -print0 | sort -z | xargs -0 sha256sum'
    docker run --rm --entrypoint bash "$upstream" -ec "$manifest" |
        docker run --rm -i --entrypoint bash "$image" -ec 'cd /app; sha256sum --check --quiet'
    image_environment='{{range .Config.Env}}{{println .}}{{end}}'
    test "$(docker image inspect --format "$image_environment" "$image" | awk '/^NVIDIA_/' | sort)" \
        = "$(docker image inspect --format "$image_environment" "$upstream" | awk '/^NVIDIA_/' | sort)"
    echo 'PASS: application files and media source pins match upstream'
fi

docker run --rm -e UV_PROJECT_ENVIRONMENT=/custom \
    --entrypoint /usr/local/bin/dispatcharr-env "$image" python -c \
    'import os; assert os.environ["UV_PROJECT_ENVIRONMENT"] == "/custom"'

# Reproduce Hotio assigning the GPU's GID before Dispatcharr configures users.
docker run --rm --entrypoint bash "$image" -ec '
    groupadd -g 60000 hotio-gpu
    mkdir -p /dev/dri
    touch /dev/dri/renderD128
    chown 0:60000 /dev/dri/renderD128
    . /app/docker/init/01-user-setup.sh
    id -G hotio | tr " " "\n" | grep -qx 60000
    test "$(getent group 60000 | cut -d: -f1)" = hotio-gpu
    . /app/docker/init/01-user-setup.sh
'

# Run against the built image without starting services or touching user data.
docker run --rm --entrypoint bash "$image" -ec '
    . /etc/os-release
    test "$ID:$VERSION_ID" = ubuntu:24.04
    test -x /init
    test -x /app/docker/entrypoint.sh
    test -s /app/frontend/dist/index.html
    test "$(getent passwd hotio | cut -d: -f7)" = /bin/bash
    python -c "import django, psycopg, celery, gevent, torch, vlc; assert vlc.libvlc_get_version()"
    uv pip check --python /dispatcharrpy/bin/python
    test -n "$(find /opt -maxdepth 1 -name "numpy-*.whl" -print -quit)"
    uwsgi --version
    ffmpeg -version
    ffprobe -version
    ffmpeg -v error -f lavfi -i color=size=16x16:duration=0.1 -c:v libx264 -f null -
    ffmpeg -v error -f lavfi -i color=size=64x64:duration=0.1 -frames:v 1 \
        -c:v libsvtav1 -preset 12 -svtav1-params lp=1 -f null -
    command -v comskip
    for binary in /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/comskip; do
        linked=$(ldd "$binary")
        if [[ "$linked" == *"not found"* ]]; then
            printf "%s\n" "$linked" >&2
            exit 1
        fi
    done
    nginx -v
    redis-server --version
    postgres=(/usr/lib/postgresql/*/bin/postgres)
    test "${#postgres[@]}" = 1
    test -x "${postgres[0]}"
    uv pip install --python /dispatcharrpy/bin/python --no-index --no-deps \
        --force-reinstall /opt/numpy-*.whl
    python -c "import numpy; assert numpy.arange(3).sum() == 3"
'

container=$(docker run -d --tmpfs /data --tmpfs /config \
    -e VPN_ENABLED=false -e UWSGI_WORKERS=1 \
    -e CELERY_MAX_WORKERS=1 -e CELERY_MIN_WORKERS=1 "$image")
trap 'docker rm -f "$container" >/dev/null' EXIT

for ((attempt = 0; attempt < 120; attempt++)); do
    if docker exec "$container" bash -o pipefail -c \
        'curl -fsS http://127.0.0.1:9191/api/accounts/initialize-superuser/ | jq -e ".superuser_exists == false"' \
        >/dev/null 2>&1; then
        docker exec "$container" curl -fsS http://127.0.0.1:9191/ >/dev/null
        docker stop -t 30 "$container" >/dev/null
        test "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0
        echo 'PASS: Hotio initialization, Dispatcharr HTTP, and graceful shutdown'
        exit 0
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$container")" != true ]; then
        break
    fi
    sleep 2
done

docker logs --tail 100 "$container"
echo 'FAIL: Dispatcharr did not become ready' >&2
exit 1
