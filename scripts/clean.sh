#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

echo "Stopping containers and removing volumes..."
docker compose -f "$BASE_DIR/docker-compose.yml" down -v || true

echo "Removing generated keystores and temp files..."
rm -f "$BASE_DIR/conf/default-connector-keystore.p12" \
      "$BASE_DIR/cert/isstbroker-keystore.p12" \
      "$BASE_DIR/cert/isstbroker-keystore.jks" || true

echo "Optionally restore working tree via git if available..."
if command -v git >/dev/null 2>&1 && [ -d "$BASE_DIR/.git" ]; then
  git -C "$BASE_DIR" restore -SW . || true
fi

echo "Clean complete."

