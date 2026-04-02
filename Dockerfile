# ─────────────────────────────────────────────────────────────
# CDN Nginx with ngx_cache_purge module
# Multi-stage build: compiles dynamic module against exact nginx version
# ─────────────────────────────────────────────────────────────
ARG NGINX_TAG=stable-alpine

FROM nginx:${NGINX_TAG} AS builder
RUN apk add --no-cache gcc make libc-dev pcre2-dev zlib-dev openssl-dev linux-headers git \
    && NGINX_VERSION=$(nginx -v 2>&1 | sed 's/nginx version: nginx\///') \
    && wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
    && tar -xzf "nginx-${NGINX_VERSION}.tar.gz" \
    && git clone --depth 1 https://github.com/nginx-modules/ngx_cache_purge.git /tmp/ngx_cache_purge \
    && cd "nginx-${NGINX_VERSION}" \
    && ./configure --with-compat --add-dynamic-module=/tmp/ngx_cache_purge \
    && make modules

# ── Final image ───────────────────────────────────────────────
FROM nginx:${NGINX_TAG}

LABEL org.opencontainers.image.source="https://github.com/CodeMindEC/s3-media-edge" \
      org.opencontainers.image.title="s3-media-edge-cdn" \
      org.opencontainers.image.description="CDN Nginx with cache purge, image resize & video slice"

COPY --from=builder /nginx-*/objs/ngx_http_cache_purge_module.so /etc/nginx/modules/

RUN apk add --no-cache curl \
    && rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /var/cache/nginx/cdn \
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
