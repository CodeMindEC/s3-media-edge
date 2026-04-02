#!/bin/sh
set -e

# ─────────────────────────────────────────────────────────────
# Only these variables are substituted in templates.
# All Nginx variables ($uri, $host, $file, $width, etc.)
# are left intact because they are NOT in this list.
# ─────────────────────────────────────────────────────────────
VARS='$IMAGOR_UPSTREAM $S3_UPSTREAM $S3_BUCKET $ALLOWED_ORIGINS_REGEX $CACHE_MAX_SIZE $CDN_DOMAIN $MAX_VIDEO_SIZE $MAX_IMG_SIZE'

# Process main config
envsubst "$VARS" < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Process server block
envsubst "$VARS" < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

# Validate before starting
nginx -t

exec "$@"
