#!/bin/sh
set -eu

# ─────────────────────────────────────────────────────────────
# Garage auto-bootstrap entrypoint
# Starts Garage, then on first boot configures layout, bucket & key
# ─────────────────────────────────────────────────────────────

MARKER="/var/lib/garage/meta/.bootstrapped"
MAX_WAIT=60

# Start Garage in background
garage server &
GARAGE_PID=$!

# Forward SIGTERM/SIGINT to Garage for graceful shutdown
trap 'kill -TERM $GARAGE_PID 2>/dev/null; wait $GARAGE_PID; exit $?' TERM INT

# Wait for API with timeout
echo "[bootstrap] Waiting for Garage admin API (timeout ${MAX_WAIT}s)..."
elapsed=0
until curl -so /dev/null http://localhost:3903/health 2>/dev/null; do
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[bootstrap] ERROR: Garage API did not become ready in ${MAX_WAIT}s"
        kill -TERM "$GARAGE_PID" 2>/dev/null
        exit 1
    fi
    sleep 1
done
echo "[bootstrap] Garage admin API is responding (${elapsed}s)."

# Only bootstrap once
if [ ! -f "$MARKER" ]; then
    echo "[bootstrap] First boot — configuring cluster..."

    # Get own node ID via 'garage node id' (returns <id>@<ip>:<port>)
    NODE_ID=$(garage node id 2>/dev/null | cut -d'@' -f1 | head -1)

    if [ -z "$NODE_ID" ]; then
        echo "[bootstrap] WARNING: Could not determine node ID. Manual setup required."
    else
        echo "[bootstrap] Node: ${NODE_ID}"

        garage layout assign -z dc1 -c "${GARAGE_CAPACITY:-50GB}" "$NODE_ID"
        garage layout apply --version 1
        echo "[bootstrap] Layout applied."

        garage bucket create "${S3_BUCKET}"
        echo "[bootstrap] Bucket '${S3_BUCKET}' created."

        garage key import -n "${S3_KEY_NAME:-default}" \
            "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}"
        echo "[bootstrap] API key imported."

        garage bucket allow --read --write --owner \
            "${S3_BUCKET}" --key "${S3_KEY_NAME:-default}"
        echo "[bootstrap] Permissions granted."

        touch "$MARKER"
        echo "[bootstrap] Cluster is ready."
    fi
else
    echo "[bootstrap] Already bootstrapped, skipping."
fi

# Wait for Garage (tini handles signal forwarding)
wait $GARAGE_PID
