#!/bin/sh
set -eu
umask 077

# Usage: register.sh NAME [SECURITY_PROFILE] [CERTFILE] [--config-dir DIR] [--keys-dir DIR]

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Defaults suitable for container mounts; override with flags
CONFIG_DIR="$SCRIPT_DIR/../.generated/config"
KEYS_DIR="$SCRIPT_DIR/../keys"
CLIENTS_DIR="$KEYS_DIR/clients"

NAME="${1:-}"
SECURITY_PROFILE="${2:-idsc:BASE_SECURITY_PROFILE}"
CERT_SRC="${3:-}"

shift 3 || true
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir)
      CONFIG_DIR="$2"; shift 2;;
    --keys-dir)
      KEYS_DIR="$2"; CLIENTS_DIR="$KEYS_DIR/clients"; shift 2;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [ -z "$NAME" ]; then
  echo "Usage: $0 NAME [SECURITY_PROFILE] [CERTFILE] [--config-dir DIR] [--keys-dir DIR]" >&2
  exit 1
fi

mkdir -p "$KEYS_DIR" "$CLIENTS_DIR" "$CONFIG_DIR"

CLIENT_CERT="$KEYS_DIR/$NAME.cert"
if [ -n "$CERT_SRC" ]; then
  [ -f "$CERT_SRC" ] || { echo "Cert not found: $CERT_SRC" >&2; exit 1; }
  cert_format="DER"
  if openssl x509 -noout -in "$CERT_SRC" 2>/dev/null; then cert_format="PEM"; fi
  openssl x509 -inform "$cert_format" -in "$CERT_SRC" -text > "$CLIENT_CERT"
else
  openssl req -newkey rsa:2048 -new -batch -nodes -x509 -days 3650 -text -keyout "$CLIENTS_DIR/${NAME}.key" -out "$CLIENT_CERT"
fi

SKI="$(grep -A1 "Subject Key Identifier" "$CLIENT_CERT" | tail -n 1 | tr -d ' ')"
AKI="$(grep -A1 "Authority Key Identifier" "$CLIENT_CERT" | tail -n 1 | tr -d ' ')"
CLIENT_ID="$SKI:keyid:$AKI"

CLIENT_CERT_SHA="$(openssl x509 -in "$CLIENT_CERT" -noout -sha256 -fingerprint | tr '[:upper:]' '[:lower:]' | tr -d : | sed 's/.*=//')"

{
  echo "- client_id: $CLIENT_ID"
  echo "  client_name: $NAME"
  echo "  grant_types: client_credentials"
  echo "  token_endpoint_auth_method: private_key_jwt"
  echo "  scope: idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
  echo "  attributes:"
  echo "  - key: idsc"
  echo "    value: IDS_CONNECTOR_ATTRIBUTES_ALL"
  echo "  - key: securityProfile"
  echo "    value: $SECURITY_PROFILE"
  echo "  - key: referringConnector"
  echo "    value: http://${NAME}.demo"
  echo "  - key: \"@type\""
  echo "    value: ids:DatPayload"
  echo "  - key: \"@context\""
  echo "    value: https://w3id.org/idsa/contexts/context.jsonld"
  echo "  - key: transportCertsSha256"
  echo "    value: $CLIENT_CERT_SHA"
} >> "$CONFIG_DIR/clients.yml"

cp "$CLIENT_CERT" "$CLIENTS_DIR/${CLIENT_ID}.cert"

# Backward-compatible logging and JSON output
echo "Copied CLIENT_CERT to $CLIENTS_DIR/${CLIENT_ID}.cert"
printf '{"client_id":"%s","client_name":"%s","client_cert":"%s"}\n' "$CLIENT_ID" "$NAME" "$CLIENTS_DIR/${CLIENT_ID}.cert"
