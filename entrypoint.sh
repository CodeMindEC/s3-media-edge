#!/bin/sh
set -eu

# CDN Nginx — Entrypoint
# envsubst ONLY listed vars; Nginx runtime vars ($uri etc.) stay intact.
VARS='$IMAGOR_UPSTREAM $S3_UPSTREAM $S3_BUCKET $ALLOWED_ORIGINS_REGEX $CACHE_MAX_SIZE $CDN_DOMAIN $MAX_VIDEO_SIZE $MAX_IMG_SIZE'

envsubst "$VARS" < /etc/nginx/nginx.conf.template        > /etc/nginx/nginx.conf
envsubst "$VARS" < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

nginx -t 2>&1 || { echo "[cdn] ERROR: nginx config test failed"; exit 1; }
echo "[cdn] Config OK — starting nginx"
exec "$@"
