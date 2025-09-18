#!/usr/bin/env bash
set -euo pipefail

FQDN=${1:-broker.example.test}
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$BASE_DIR/generated/broker-dev"
mkdir -p "$OUT_DIR"

openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout "$OUT_DIR/broker.key" -out "$OUT_DIR/broker.crt" \
  -subj "/CN=$FQDN" -days 365 \
  -addext "subjectAltName=DNS:$FQDN"

echo "Dev-only broker cert generated in $OUT_DIR (DO NOT USE IN PROD)"

