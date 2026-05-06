# ─────────────────────────────────────────────────────────────
# CDN Nginx with Alpine-packaged ngx_cache_purge module
# ─────────────────────────────────────────────────────────────
ARG ALPINE_VERSION=3.21

FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.source="https://github.com/CodeMindEC/s3-media-edge" \
      org.opencontainers.image.title="s3-media-edge-cdn" \
      org.opencontainers.image.description="CDN Nginx with cache purge, image resize & video slice"

RUN for attempt in 1 2 3 4 5; do \
        apk add --no-cache nginx nginx-mod-http-cache-purge curl gettext && break; \
        if [ "$attempt" = 5 ]; then exit 1; fi; \
        sleep $((attempt * 5)); \
    done \
    && rm -f /etc/nginx/http.d/default.conf /etc/nginx/conf.d/default.conf \
    && mkdir -p /etc/nginx/conf.d /etc/nginx/templates /var/cache/nginx/cdn /var/log/nginx \
    && chown -R nginx:nginx /var/cache/nginx/cdn /var/log/nginx \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

COPY entrypoint.sh /entrypoint.sh
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY conf.d/default.conf.template /etc/nginx/templates/default.conf.template
RUN chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
