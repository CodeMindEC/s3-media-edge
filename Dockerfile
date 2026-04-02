# ─────────────────────────────────────────────────────────────
# CDN Nginx with ngx_cache_purge module (multi-arch)
# Multi-stage build: compiles dynamic module against exact nginx version
# ─────────────────────────────────────────────────────────────

FROM nginx:stable-alpine AS builder

RUN apk add --no-cache \
    gcc make libc-dev pcre2-dev zlib-dev openssl-dev linux-headers git

# Download nginx source matching the installed version
RUN NGINX_VERSION=$(nginx -v 2>&1 | sed 's/nginx version: nginx\///') \
    && wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
    && tar -xzf "nginx-${NGINX_VERSION}.tar.gz" \
    && mv "nginx-${NGINX_VERSION}" /tmp/nginx-src

# Clone ngx_cache_purge (maintained fork)
RUN git clone --depth 1 https://github.com/nginx-modules/ngx_cache_purge.git /tmp/ngx_cache_purge

# Build as dynamic module
RUN cd /tmp/nginx-src \
    && ./configure --with-compat --add-dynamic-module=/tmp/ngx_cache_purge \
    && make modules

# ── Final image ───────────────────────────────────────────────
FROM nginx:stable-alpine

COPY --from=builder /tmp/nginx-src/objs/ngx_http_cache_purge_module.so /etc/nginx/modules/

RUN rm -f /etc/nginx/conf.d/default.conf

COPY entrypoint.sh /entrypoint.sh
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY conf.d/default.conf.template /etc/nginx/templates/default.conf.template

RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/cache/nginx/cdn \
    && chown nginx:nginx /var/cache/nginx/cdn

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
