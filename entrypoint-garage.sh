#!/bin/sh
set -e

# ─────────────────────────────────────────────────────────────
# Garage auto-bootstrap entrypoint
# Starts Garage, then on first boot configures layout, bucket & key
# ─────────────────────────────────────────────────────────────

MARKER="/var/lib/garage/meta/.bootstrapped"

# Start Garage in background
/garage server &
GARAGE_PID=$!

# Wait for API to be ready
echo "[bootstrap] Waiting for Garage API..."
until curl -sf http://localhost:3900/health > /dev/null 2>&1; do
    sleep 1
done
echo "[bootstrap] Garage API is ready."

# Only bootstrap once
if [ ! -f "$MARKER" ]; then
    echo "[bootstrap] First boot detected — configuring cluster..."

    # Get own node ID
    NODE_ID=$(/garage status 2>/dev/null | grep "NO ROLE" | awk '{print $1}')
    if [ -z "$NODE_ID" ]; then
        NODE_ID=$(/garage status 2>/dev/null | tail -n +2 | head -1 | awk '{print $1}')
    fi

    if [ -n "$NODE_ID" ]; then
        echo "[bootstrap] Assigning layout to node ${NODE_ID}..."
        /garage layout assign -z dc1 -c "${GARAGE_CAPACITY:-50GB}" "$NODE_ID"
        /garage layout apply --version 1

        echo "[bootstrap] Creating bucket '${S3_BUCKET}'..."
        /garage bucket create "${S3_BUCKET}"

        echo "[bootstrap] Importing API key..."
        /garage key import -n "${S3_KEY_NAME:-default}" \
            "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}"

        echo "[bootstrap] Granting permissions..."
        /garage bucket allow --read --write --owner \
            "${S3_BUCKET}" --key "${S3_KEY_NAME:-default}"

        touch "$MARKER"
        echo "[bootstrap] Done! Cluster is ready."
    else
        echo "[bootstrap] WARNING: Could not determine node ID. Manual setup required."
    fi
else
    echo "[bootstrap] Already bootstrapped, skipping setup."
fi

# Wait for Garage process
wait $GARAGE_PID
