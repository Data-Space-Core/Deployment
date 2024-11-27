#!/bin/bash

# Function to check and create a directory
check_and_create_dir() {
  if [ ! -d "$1" ]; then
    echo "Directory $1 is missing. Creating it now."
    mkdir -p "$1"
  else
    echo "Directory $1 already exists."
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
elif [ -f "$OUT_FILE" ]; then
  echo "File $OUT_FILE already exists. It will be overwritten."
  rm -f "$OUT_FILE"
fi

# Generate PKCS#12 file
CERT_DIR="/home/vmuser/ryan/BLABLA/cert_2024"

echo "Generating PKCS#12 file..."
openssl pkcs12 -export -out "$OUT_FILE" \
    -inkey "$CERT_DIR/server.key" \
    -in "$CERT_DIR/Certificate CRT/STAR_collab-cloud_eu.crt" \
    -passout pass:password

if [ $? -eq 0 ]; then
  echo "PKCS#12 file successfully generated at $OUT_FILE"
else
  echo "Error: Failed to generate PKCS#12 file."
  exit 1
fi

# Reminder for configuration
echo "Please ensure that the produced file name matches the connector's config.json:"
echo '  "ids:keyStore" : {'
echo '    "@id" : "file:///conf/default-connector-keystore.p12"'
echo '  }'
echo "If needed, rename the generated file to 'default-connector-keystore.p12' or update the configuration."

# Register connector to DAPS
REGISTER_SCRIPT="scripts/register.sh"
CONNECTOR_NAME="default-connector"
SECURITY_PROFILE="BASE_SECURITY_PROFILE"
CERT_FILE="$CERT_DIR/Certificate CRT/STAR_collab-cloud_eu.crt"

if [ -x "$REGISTER_SCRIPT" ]; then
  echo "Registering connector to DAPS..."
  $REGISTER_SCRIPT "$CONNECTOR_NAME" "$SECURITY_PROFILE" "$CERT_FILE"

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
