#!/bin/bash
set -euo pipefail

image=${1:-dispatcharr-hotio:test}
upstream=${2:-}

if [[ -n "$upstream" ]]; then
    for executable in ffmpeg ffprobe comskip; do
        test "$(docker run --rm --entrypoint sha256sum "$image" "/usr/local/bin/$executable")" \
            = "$(docker run --rm --entrypoint sha256sum "$upstream" "/usr/local/bin/$executable")"
    done
    packages='import importlib.metadata as m, json; print(json.dumps(sorted((d.metadata["Name"], d.version) for d in m.distributions())))'
    test "$(docker run --rm --entrypoint /dispatcharrpy/bin/python "$image" -c "$packages")" \
        = "$(docker run --rm --entrypoint /dispatcharrpy/bin/python "$upstream" -c "$packages")"
    manifest='cd /app; find . -type f -print0 | sort -z | xargs -0 sha256sum'
    docker run --rm --entrypoint bash "$upstream" -ec "$manifest" \
        | docker run --rm -i --entrypoint bash "$image" -ec 'cd /app; sha256sum --check --quiet'
    image_environment='{{range .Config.Env}}{{println .}}{{end}}'
    test "$(docker image inspect --format "$image_environment" "$image" | awk '/^NVIDIA_/' | sort)" \
        = "$(docker image inspect --format "$image_environment" "$upstream" | awk '/^NVIDIA_/' | sort)"
    echo 'PASS: application, media binaries, and Python packages match upstream'
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
    test -x /init
    test -x /app/docker/entrypoint.sh
    test -s /app/frontend/dist/index.html
    test "$(getent passwd hotio | cut -d: -f7)" = /bin/bash
    python -c "import django, psycopg, celery, gevent, torch"
    uwsgi --version
    ffmpeg -version
    ffprobe -version
    ffmpeg -v error -f lavfi -i color=size=16x16:duration=0.1 -c:v libx264 -f null -
    command -v comskip
    nginx -v
    redis-server --version
    postgres=(/usr/lib/postgresql/*/bin/postgres)
    test "${#postgres[@]}" = 1
    test -x "${postgres[0]}"
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
