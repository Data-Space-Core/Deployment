#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (script directory)
BASE_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '%s\n' "$*"; }
err() { printf 'Error: %s\n' "$*" >&2; }

# Dependency checks
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing dependency: $1"; return 1; }
}

say "Preflight: checking dependencies (docker, openssl, keytool)"
need_cmd docker
need_cmd openssl
need_cmd keytool || {
  err "keytool not found. Install a JRE (e.g., openjdk-17-jre)."; exit 1; }

# Docker access check
if ! docker info >/dev/null 2>&1; then
  err "Docker not accessible. Ensure Docker is running and your user is in the 'docker' group (then re-login)."
  exit 1
fi

# Utility: check and create directory
check_and_create_dir() {
  if [ ! -d "$1" ]; then
    say "Directory $1 is missing. Creating it now."
    mkdir -p "$1"
  else
    say "Directory $1 already exists."
  fi
}

check_file_exists() {
  if [ ! -f "$1" ]; then
    err "Required file missing: $1"
    return 1
  else
    say "File $1 exists."
    return 0
  fi
}

# Check required directories
check_and_create_dir "$BASE_DIR/cert"
check_and_create_dir "$BASE_DIR/conf"
check_and_create_dir "$BASE_DIR/keys"

# Ensure no directory exists at the location of the keystore file
OUT_FILE="$BASE_DIR/conf/default-connector-keystore.p12"
if [ -d "$OUT_FILE" ]; then
  echo "Removing mistakenly created directory at $OUT_FILE"
  rm -rf "$OUT_FILE"
fi

# Prepare files
NGINX_CONF="$BASE_DIR/nginx.development.conf"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
CONNECTORCONF="$BASE_DIR/conf/config.json"

# Ask for the Fully Qualified Domain Name (FQDN)
echo "Please provide the Fully Qualified Domain Name (FQDN):"
read -r FQDN
# If FQDN is empty, try to auto-detect it
if [[ -z "$FQDN" ]]; then
  SERVER_IP=$(ip addr show scope global | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
  if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Could not determine the server's IP address."
    exit 1
  fi

  # Use dig to resolve FQDN from IP
  FQDN=$(dig +short -x "$SERVER_IP" | sed 's/\.$//')

  if [[ -z "$FQDN" ]]; then
    echo "❌ Could not resolve FQDN from IP address ($SERVER_IP)."
    exit 1
  fi

  echo "✅ Auto-detected FQDN: $FQDN"
else
  echo "✅ Using provided FQDN: $FQDN"
fi

# Ask for the path to the SSL certificate directory
echo "Please provide the path to the SSL certificates:"
read -r CERT_PATH
# Check if directory exists
if [[ ! -d "$CERT_PATH" ]]; then
  echo "❌ Directory does not exist: $CERT_PATH"
  exit 1
fi

# Ask for the path to the SSL cert file
echo "Please provide the name of public certificate file:"
read -r CERT_FILE
# Check if file exists
if [[ ! -f "$CERT_PATH/$CERT_FILE" ]]; then
  echo "❌ Public certificate file not found: $CERT_PATH/$CERT_FILE"
  exit 1
fi
# Ask for the path to the SSL private key
echo "Please provide the name of private key file:"
read -r KEY_FILE
# Check if file exists
if [[ ! -f "$CERT_PATH/$KEY_FILE" ]]; then
  echo "❌ Private key file not found: $CERT_PATH/$KEY_FILE"
  exit 1
fi

# Ask for the path to chained SSL public key
echo "Please provide the name of chained public certificate file:"
read -r CHAIN_FILE

# Check if file exists
if [[ ! -f "$CERT_PATH/$CHAIN_FILE" ]]; then
  echo "❌ Chained certificate file not found: $CERT_PATH/$CHAIN_FILE"
  exit 1
fi

# Check if the nginx configuration file exists
if [[ ! -f "$NGINX_CONF" ]]; then
    echo "Error: nginx.development.conf file not found in the current directory."
    exit 1
fi

# Check if the docker-compose configuration file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Error: docker-compose.yml file not found in the current directory."
    exit 1
fi

sed -i "s|__HOST__|$FQDN|g" "$NGINX_CONF"
sed -i "s|__CERT__|$CHAIN_FILE|g" "$NGINX_CONF"
sed -i "s|__KEY__|$KEY_FILE|g" "$NGINX_CONF"
sed -i "s|__HOST__|$FQDN|g" "$COMPOSE_FILE" || true
sed -i "s|__HOST__|$FQDN|g" "$CONNECTORCONF" || true
sed -i "s|__CERTDIRECTORY__|$CERT_PATH|g" "$COMPOSE_FILE" || true
sed -i "s|__HOST__|$FQDN|g" "$BASE_DIR/config/omejdn.yml" || true
# Check required files
MISSING_FILES=0
CERT_DIR="$BASE_DIR/cert"
REQUIRED_FILES=(
  "$CERT_PATH/$KEY_FILE"
  "$CERT_PATH/$CERT_FILE"
  "$BASE_DIR/conf/config.json"
  "$BASE_DIR/conf/truststore.p12"
)

for FILE in "${REQUIRED_FILES[@]}"; do
  check_file_exists "$FILE" || MISSING_FILES=$((MISSING_FILES + 1))
done


if [ $MISSING_FILES -ne 0 ]; then
  echo "Error: One or more required files are missing. Please check and try again."
  exit 1
fi

# Validate cert/key match (modulus)
say "Validating certificate and key match..."
cert_md5=$(openssl x509 -noout -modulus -in "$CERT_PATH/$CERT_FILE" | openssl md5 | awk '{print $2}')
key_md5=$(openssl rsa  -noout -modulus -in "$CERT_PATH/$KEY_FILE"  | openssl md5 | awk '{print $2}')
if [ "${cert_md5:-x}" != "${key_md5:-y}" ]; then
  err "Certificate and private key do not match (modulus mismatch)."
  exit 1
fi

# Register connector to DAPS
REGISTER_SCRIPT="$BASE_DIR/scripts/register.sh"
CONNECTOR_NAME="default-connector"
SECURITY_PROFILE="idsc:BASE_SECURITY_PROFILE"

if [ -x "$REGISTER_SCRIPT" ]; then
  echo "Registering connector to DAPS... with certificate at $CERT_PATH/$CERT_FILE"
  "$REGISTER_SCRIPT" "$CONNECTOR_NAME" "$SECURITY_PROFILE" "$CERT_PATH/$CERT_FILE"

  if [ $? -eq 0 ]; then
    echo "Connector successfully registered to DAPS!"
  else
    echo "Error: Failed to register connector to DAPS."
    exit 1
  fi
else
  echo "Error: Registration script $REGISTER_SCRIPT not found or not executable."
  exit 1
fi

# Generate PKCS#12 file
echo "Generating Connector PKCS#12 file..."
openssl pkcs12 -export -out "$OUT_FILE" \
    -inkey "$CERT_PATH/$KEY_FILE" \
    -in "$CERT_PATH/$CERT_FILE" \
    -passout pass:password

if [ $? -eq 0 ]; then
  echo "PKCS#12 file successfully generated at $OUT_FILE"
else
  echo "Error: Failed to generate PKCS#12 file."
  exit 1
fi

# Register Broker with DAPS
CONNECTOR_NAME="default-broker"
SECURITY_PROFILE="idsc:BASE_SECURITY_PROFILE"

if [ -x "$REGISTER_SCRIPT" ]; then
  echo "Registering broker to DAPS... with certificate at $CERT_PATH/$CERT_FILE"
  "$REGISTER_SCRIPT" "$CONNECTOR_NAME" "$SECURITY_PROFILE" "$CERT_PATH/$CERT_FILE"

  if [ $? -eq 0 ]; then
    echo "Connector successfully registered to DAPS!"
  else
    echo "Error: Failed to register connector to DAPS."
    exit 1
  fi
else
  echo "Error: Registration script $REGISTER_SCRIPT not found or not executable."
  exit 1
fi

# Generate PKCS#12 file
echo "Generating Broker PKCS#12 file..."
openssl pkcs12 -export -out "$BASE_DIR/cert/isstbroker-keystore.p12" \
    -inkey "$CERT_PATH/$KEY_FILE" \
    -in "$CERT_PATH/$CERT_FILE" \
    -passout pass:password
if [ $? -eq 0 ]; then
  echo "PKCS#12 file successfully generated at $OUT_FILE"
else
  echo "Error: Failed to generate PKCS#12 file."
  exit 1
fi

chmod -R u=rw,go=r "$BASE_DIR/cert" || true
keytool -importkeystore \
  -srckeystore "$BASE_DIR/cert/isstbroker-keystore.p12" -srcstoretype PKCS12 \
  -destkeystore "$BASE_DIR/cert/isstbroker-keystore.jks" -deststoretype JKS \
  -srcstorepass password -deststorepass password

# Optionally copy JKS to cert path for external usage
cp -f "$BASE_DIR/cert/isstbroker-keystore.jks" "$CERT_PATH/" || true

# Ensure proper permissions for the `conf` directory and generated keystore
echo "Setting permissions for the 'conf' directory and its files..."
chmod -R u=rwX,go=rX "$BASE_DIR/conf" || true

# Reminder for configuration
echo "Please ensure that the produced file name matches the connector's config.json:"
echo '  "ids:keyStore" : {'
echo '    "@id" : "file:///conf/default-connector-keystore.p12"'
echo '  }'
echo "If needed, rename the generated file to 'default-connector-keystore.p12' or update the configuration."

# GHCR pull preflight (one representative public image)
say "Preflight: testing anonymous GHCR pull for omejdn-server:latest"
if ! docker pull -q ghcr.io/data-space-core/dsil-omejdn-server/omejdn-server:latest >/dev/null 2>&1; then
  err "Cannot pull public images anonymously. If images are private, run: docker login ghcr.io (PAT needs read:packages)."
fi

# Docker Compose operations
echo "Stopping and removing existing containers..."
docker compose -f "$COMPOSE_FILE" down -v || true

echo "Pulling updated images..."
docker compose -f "$COMPOSE_FILE" pull

echo "Building and starting services..."
docker compose -f "$COMPOSE_FILE" up --build -d

# Verify all services are running
if [ $? -eq 0 ]; then
  echo "All services are running and ready!"
else
  echo "Error: Services failed to start. Check logs for details."
  exit 1
fi
