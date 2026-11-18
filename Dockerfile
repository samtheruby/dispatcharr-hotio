ARG UPSTREAM_IMAGE
FROM ${UPSTREAM_IMAGE} AS upstream
ARG DISPATCHARR_VERSION
COPY scripts/export_runtime.py /tmp/export_runtime.py
RUN /dispatcharrpy/bin/python /tmp/export_runtime.py "$DISPATCHARR_VERSION"

# Bake supplies the runtime built from the pinned Hotio base.
# hadolint ignore=DL3006
FROM runtime-base AS dependencies
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY --from=upstream /dispatcharr-export/ /usr/local/share/dispatcharr-upstream/
# Application files can cross OS versions; native runtime artifacts are rebuilt.
RUN test "$(dpkg --print-architecture)" = "$(< /usr/local/share/dispatcharr-upstream/architecture)"
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
COPY --from=upstream /app/docker/nginx.conf /etc/nginx/sites-enabled/default
EXPOSE 9191
# Hotio completes VPN initialization before applying Dispatcharr's environment.
ENTRYPOINT ["/init"]
CMD ["/command/with-contenv", "/usr/local/bin/dispatcharr-env", "/app/docker/entrypoint.sh"]
