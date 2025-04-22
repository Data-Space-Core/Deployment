#!/bin/bash

# Login to GHCR
sudo docker login ghcr.io 
# Function to check and create a directory
check_and_create_dir() {
  if [ ! -d "$1" ]; then
    echo "Directory $1 is missing. Creating it now."
    mkdir -p "$1"
  else
    echo "Directory $1 already exists."
  fi
}

check_file_exists() {
    if ! sudo test -f "$1"; then
        echo "Error: Required file $1 is missing or inaccessible!"
        return 1
    else
        echo "File $1 exists."
        return 0
    fi
}

# Check required directories
check_and_create_dir "./cert"
check_and_create_dir "./conf"
check_and_create_dir "./keys"

# Ensure no directory exists at the location of the keystore file
OUT_FILE="./conf/default-connector-keystore.p12"
if [ -d "$OUT_FILE" ]; then
  echo "Removing mistakenly created directory at $OUT_FILE"
  rm -rf "$OUT_FILE"
fi

# Prepare files
NGINX_CONF="./nginx.development.conf"
COMPOSE_FILE="./docker-compose.yml"
CONNECTORCONF="./conf/config.json"

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
sed -i "s|__HOST__|$FQDN|g" "$COMPOSE_FILE"
sed -i "s|__HOST__|$FQDN|g" "$CONNECTORCONF"
sed -i "s|__CERTDIRECTORY__|$CERT_PATH|g" "$COMPOSE_FILE"
sed -i "s|__HOST__|$FQDN|g" "./config/omejdn.yml"
# Check required files
MISSING_FILES=0
CERT_DIR="./cert"
REQUIRED_FILES=(
  "$CERT_PATH/$KEY_FILE"
  "$CERT_PATH/$CERT_FILE"
  "./conf/config.json"
  "./conf/truststore.p12"
)

for FILE in "${REQUIRED_FILES[@]}"; do
  check_file_exists "$FILE" || MISSING_FILES=$((MISSING_FILES + 1))
done


if [ $MISSING_FILES -ne 0 ]; then
  echo "Error: One or more required files are missing. Please check and try again."
  exit 1
fi

# Register connector to DAPS
REGISTER_SCRIPT="scripts/register.sh"
CONNECTOR_NAME="default-connector"
SECURITY_PROFILE="idsc:BASE_SECURITY_PROFILE"

if [ -x "$REGISTER_SCRIPT" ]; then
  echo "Registering connector to DAPS... with certificate at $CERT_PATH/$CERT_FILE"
  $REGISTER_SCRIPT "$CONNECTOR_NAME" "$SECURITY_PROFILE" "$CERT_PATH/$CERT_FILE"

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
  $REGISTER_SCRIPT "$CONNECTOR_NAME" "$SECURITY_PROFILE" "$CERT_PATH/$CERT_FILE"

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
openssl pkcs12 -export -out ./cert/isstbroker-keystore.p12 \
    -inkey "$CERT_PATH/$KEY_FILE" \
    -in "./keys/$CONNECTOR_NAME.cert" \
    -passout pass:password
if [ $? -eq 0 ]; then
  echo "PKCS#12 file successfully generated at $OUT_FILE"
else
  echo "Error: Failed to generate PKCS#12 file."
  exit 1
fi
sudo chmod -R 644 ./cert/*
keytool -importkeystore -srckeystore ./cert/isstbroker-keystore.p12 -srcstoretype PKCS12 -destkeystore ./cert/isstbroker-keystore.jks -deststoretype JKS -srcstorepass password -deststorepass password

# Ensure proper permissions for the `conf` directory and `default-connector-keystore.p12`
echo "Setting permissions for the 'conf' directory and its files..."
sudo chmod -R 755 ./conf
sudo chown -R $(id -u):$(id -g) ./conf

# Reminder for configuration
echo "Please ensure that the produced file name matches the connector's config.json:"
echo '  "ids:keyStore" : {'
echo '    "@id" : "file:///conf/default-connector-keystore.p12"'
echo '  }'
echo "If needed, rename the generated file to 'default-connector-keystore.p12' or update the configuration."

# Docker Compose operations
echo "Stopping and removing existing containers..."
sudo docker compose down -v

echo "Pulling updated images..."
sudo docker compose pull

echo "Building and starting services..."
sudo docker compose up --build -d

# Verify all services are running
if [ $? -eq 0 ]; then
  echo "All services are running and ready!"
else
  echo "Error: Services failed to start. Check logs for details."
  exit 1
fi
