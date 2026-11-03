ARG UPSTREAM_IMAGE
ARG HOTIO_BASE_IMAGE=ghcr.io/hotio/base:noblevpn
FROM ${UPSTREAM_IMAGE} AS upstream
ARG DISPATCHARR_VERSION
COPY scripts/export_runtime.py /tmp/export_runtime.py
RUN /dispatcharrpy/bin/python /tmp/export_runtime.py "$DISPATCHARR_VERSION"

FROM ${HOTIO_BASE_IMAGE} AS dependencies
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=upstream /etc/os-release /tmp/upstream-os-release
COPY --from=upstream /dispatcharr-export/ /usr/local/share/dispatcharr-upstream/
# Native libraries and the Python environment require a matching OS and architecture.
RUN . /etc/os-release && own_os="$ID:$VERSION_ID" \
    && . /tmp/upstream-os-release \
    && if [[ "$own_os" != "$ID:$VERSION_ID" ]] \
       || [[ "$(dpkg --print-architecture)" != "$(< /usr/local/share/dispatcharr-upstream/architecture)" ]]; then \
       echo "Incompatible upstream runtime: $ID:$VERSION_ID versus Hotio $own_os. Review packaging before publishing." >&2; exit 1; fi

# Use upstream's repositories and package requirements; retain Hotio's VPN packages.
COPY --from=upstream /etc/apt/ /etc/apt/
COPY --from=upstream /usr/share/keyrings/ /usr/share/keyrings/
RUN apt-get update \
    && cut -f1 /usr/local/share/dispatcharr-upstream/packages.tsv \
       | xargs apt-get install --no-install-recommends -y \
    && rm -rf /var/lib/apt/lists/*

COPY --from=upstream /usr/local/ /usr/local/
COPY --from=upstream /etc/ld.so.conf.d/ /etc/ld.so.conf.d/
COPY --from=upstream /dispatcharrpy/ /dispatcharrpy/
COPY --from=upstream /opt/ /opt/
COPY --from=upstream /bin/uv /bin/uvx /bin/
COPY scripts/with_upstream_env.sh /usr/local/bin/dispatcharr-env
RUN ldconfig && chmod +x /usr/local/bin/dispatcharr-env \
    && mkdir -p /data && groupadd --system --force render \
    && usermod -s /bin/bash hotio
ENV VIRTUAL_ENV=/dispatcharrpy \
    PATH="/dispatcharrpy/bin:$PATH" \
    NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
    NVIDIA_VISIBLE_DEVICES=all \
    POSTGRES_USER=hotio \
    POSTGRES_DB=dispatcharr \
    DISPATCHARR_ENV=aio \
    WEBUI_PORTS=9191/tcp

FROM dependencies AS final
WORKDIR /app
COPY --from=upstream /app/ /app/
COPY --from=upstream /etc/nginx/ /etc/nginx/
EXPOSE 9191
# Hotio completes VPN initialization before applying Dispatcharr's environment.
CMD ["/command/with-contenv", "/usr/local/bin/dispatcharr-env", "/app/docker/entrypoint.sh"]
