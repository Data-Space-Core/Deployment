#!/usr/bin/env bash
set -euo pipefail

# Idempotent runner: prepares generated configs and starts stack without mutating tracked files.

umask 077

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
GEN_DIR="$ROOT_DIR/.generated"
CERT_DIR="$ROOT_DIR/cert"
CONF_DIR="$ROOT_DIR/conf"
TEMPLATE_NGX="$ROOT_DIR/nginx.template.conf"
OUT_NGX="$GEN_DIR/nginx.conf"
OUT_CONNECTOR_CONF="$GEN_DIR/config.json"
GEN_CONFIG_DIR="$GEN_DIR/config"

mkdir -p "$GEN_DIR" "$GEN_CONFIG_DIR" "$CERT_DIR" "$ROOT_DIR/keys" "$ROOT_DIR/upload"
cp -R "$ROOT_DIR/config/"* "$GEN_CONFIG_DIR"/ 2>/dev/null || true

if [ -f "$ROOT_DIR/.env" ]; then
  # shellcheck disable=SC2046
  export $(grep -v "^#" "$ROOT_DIR/.env" | grep -E "^[A-Za-z0-9_]+=" | xargs -0 -I {} echo {})
fi

FQDN=${DOMAIN:-}
if [ -z "${FQDN:-}" ]; then
  read -rp "FQDN (e.g. example.com): " FQDN
fi
if [ -z "${FQDN:-}" ]; then
  echo "FQDN is required." >&2; exit 1
fi

ALLOWED_ORIGIN=${ALLOWED_ORIGIN:-"https://$FQDN"}

read -rp "Path to public certificate file: " PUBLIC_CERT_FILE
read -rp "Path to private key file: " PRIVATE_KEY_FILE
read -rp "Path to chained certificate file (fullchain): " CHAIN_CERT_FILE

for f in "$PUBLIC_CERT_FILE" "$PRIVATE_KEY_FILE" "$CHAIN_CERT_FILE"; do
  [ -f "$f" ] || { echo "Missing file: $f" >&2; exit 1; }
done

# Copy certs into ./cert with safe permissions
cp "$PUBLIC_CERT_FILE" "$CERT_DIR/server.crt"
cp "$CHAIN_CERT_FILE" "$CERT_DIR/fullchain.crt"
cp "$PRIVATE_KEY_FILE" "$CERT_DIR/server.key"
chmod 600 "$CERT_DIR/server.key"
chmod 644 "$CERT_DIR"/*.crt || true

# Render nginx config from template
if [ ! -f "$TEMPLATE_NGX" ]; then
  echo "Missing nginx.template.conf" >&2; exit 1
fi
export FQDN CERT_FILE="fullchain.crt" KEY_FILE="server.key" ALLOWED_ORIGIN
awk '{
  line=$0;
  gsub(/\$\{FQDN\}/, ENVIRON["FQDN"], line);
  gsub(/\$\{CERT_FILE\}/, ENVIRON["CERT_FILE"], line);
  gsub(/\$\{KEY_FILE\}/, ENVIRON["KEY_FILE"], line);
  gsub(/\$\{ALLOWED_ORIGIN\}/, ENVIRON["ALLOWED_ORIGIN"], line);
  print line;
}' "$TEMPLATE_NGX" > "$OUT_NGX"

# Render connector config from template
CONNECTOR_TEMPLATE="$CONF_DIR/config.template.json"
if [ ! -f "$CONNECTOR_TEMPLATE" ]; then
  echo "Missing conf/config.template.json" >&2; exit 1
fi
awk '{
  line=$0;
  gsub(/\$\{FQDN\}/, ENVIRON["FQDN"], line);
  print line;
}' "$CONNECTOR_TEMPLATE" > "$OUT_CONNECTOR_CONF"

# Ensure truststore is in place (copied from repo conf or provided by user)
if [ -f "$CONF_DIR/truststore.p12" ]; then
  cp "$CONF_DIR/truststore.p12" "$GEN_CONFIG_DIR/truststore.p12"
fi

# Register default connector and broker in generated config dir
REGISTER_SCRIPT="$ROOT_DIR/scripts/register.sh"
if [ ! -x "$REGISTER_SCRIPT" ]; then
  echo "Registration script not executable; fixing perms"; chmod +x "$REGISTER_SCRIPT"
fi

echo "Registering default connector and broker to DAPS using provided public cert..."
"$REGISTER_SCRIPT" default-connector idsc:BASE_SECURITY_PROFILE "$CERT_DIR/server.crt" --config-dir "$GEN_CONFIG_DIR" --keys-dir "$ROOT_DIR/keys"
"$REGISTER_SCRIPT" default-broker idsc:BASE_SECURITY_PROFILE "$CERT_DIR/server.crt" --config-dir "$GEN_CONFIG_DIR" --keys-dir "$ROOT_DIR/keys"

# Generate PKCS#12 files
echo "Generating Connector PKCS#12 file..."
openssl pkcs12 -export -out "$ROOT_DIR/conf/default-connector-keystore.p12" -inkey "$CERT_DIR/server.key" -in "$CERT_DIR/server.crt" -passout pass:password
chmod 600 "$ROOT_DIR/conf/default-connector-keystore.p12"

echo "Generating Broker PKCS#12 file..."
openssl pkcs12 -export -out "$CERT_DIR/isstbroker-keystore.p12" -inkey "$CERT_DIR/server.key" -in "$ROOT_DIR/keys/default-broker.cert" -passout pass:password || true

echo "Converting Broker keystore to JKS..."
if command -v keytool >/dev/null 2>&1; then
  keytool -importkeystore -srckeystore "$CERT_DIR/isstbroker-keystore.p12" -srcstoretype PKCS12 -destkeystore "$CERT_DIR/isstbroker-keystore.jks" -deststoretype JKS -srcstorepass password -deststorepass password || true
fi

echo "Bringing up stack with Docker Compose..."
docker compose down -v || true
docker compose pull || true
docker compose up --build -d

echo "All services started. Nginx serving for $FQDN"
