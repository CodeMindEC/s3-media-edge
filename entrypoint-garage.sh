#!/bin/sh
set -eu

# Garage auto-bootstrap entrypoint
# Starts Garage, then on first boot configures layout, bucket & key.

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
        SHORT_ID=$(echo "$NODE_ID" | cut -c1-16)

        # --- Layout (skip if node already has a role) ---
        if garage layout show 2>/dev/null | grep -q "$SHORT_ID"; then
            echo "[bootstrap] Layout already has this node, skipping layout."
        else
            # Clear any stale staged changes from previous failed attempts
            garage layout revert 2>/dev/null || true
            garage layout assign -z dc1 -c "${GARAGE_CAPACITY:-50GB}" "$NODE_ID"

            # Determine next layout version dynamically
            CURRENT_VER=$(garage layout show 2>/dev/null \
                | grep "Current cluster layout version" \
                | awk '{print $NF}')
            NEXT_VER=$(( ${CURRENT_VER:-0} + 1 ))
            garage layout apply --version "$NEXT_VER"
            echo "[bootstrap] Layout applied (version ${NEXT_VER})."
        fi

        # --- Bucket (idempotent) ---
        garage bucket create "${S3_BUCKET}" 2>/dev/null || true
        echo "[bootstrap] Bucket '${S3_BUCKET}' ensured."

        # --- API key (idempotent) ---
        garage key import -n "${S3_KEY_NAME:-default}" \
            "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" 2>/dev/null || true
        echo "[bootstrap] API key ensured."

        # --- Permissions (idempotent) ---
        garage bucket allow --read --write --owner \
            "${S3_BUCKET}" --key "${S3_KEY_NAME:-default}" 2>/dev/null || true
        echo "[bootstrap] Permissions granted."

        touch "$MARKER"
        echo "[bootstrap] Cluster is ready."
    fi
else
    echo "[bootstrap] Already bootstrapped, skipping."
fi

# Wait for Garage (tini handles signal forwarding)
wait $GARAGE_PID
