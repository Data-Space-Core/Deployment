# Deployment

This repo deploys the DS Core stack (Connector, DAPS, Broker, Nginx). Before running, ensure you have a Fully Qualified Domain Name (FQDN) and valid SSL certificates for that FQDN.

Run the installer (no sudo):
```
./runner.sh
```

The script prompts for:
- FQDN
- Certificate directory (e.g., `/etc/cert`)
- Public certificate filename (e.g., `fullchain.pem`)
- Private key filename (e.g., `privkey.pem`)
- Chained certificate filename (for Nginx TLS, often same as public cert)

During preflight it checks for `docker`, `openssl`, and `keytool`, validates Docker access, verifies the certificate and key match (modulus), and performs a GHCR pull test. If images are private in your environment, log in using a PAT with `read:packages` permissions:
```
docker login ghcr.io
```

Certificate guidance:
- Provide a chained certificate file that contains server cert + intermediates + root.
- Keep the private key safe; it is not part of typical CA delivery.

Note: Re-running the installer is idempotent for most steps, but if you want to reset local changes you can use the helper script:
```
./scripts/clean.sh
```

# Included Components

This installation package include following dataspace components:

- IDSA Data Space Connector
- IDSA Omejdn DAPS Identity provider
- IDSA Omejdn DAPS Web User Interface
- IDSA Data Space Broker

It also provides supporting components

- PostgreSQL Database for data space connector persistency
- NGINX Reverse Proxy to act as gateway to the different components

# Usage

Here is short list of available user interfaces in the deployment:
## Connector
- https://<host>/connector/api/docs - Swagger UI for the connector
## Broker
- https://<host>/broker/fuseki/
## DAPS 
- https://<host>/

## Prerequisites
- Ubuntu 22.04 LTS (or compatible)
- Docker 24+ and Docker Compose v2
- OpenSSL 1.1+/3.0+
- Java Runtime Environment with `keytool` (e.g., OpenJDK 17)

Install JRE on Debian/Ubuntu:
```
sudo apt-get update && sudo apt-get install -y openjdk-17-jre
```

Ensure Docker access without sudo. Add your user to the `docker` group and re-login if needed:
```
sudo usermod -aG docker "$USER"
```

## Certificate Model
- Production: distinct certs per FQDN and service as required by your setup.
- Testing: you may reuse a cert for convenience.
- A dev-only broker TLS helper is provided:
```
./scripts/generate-broker-cert.sh broker.dev.local
```

## GHCR Images
Images are published under `ghcr.io/data-space-core`.
- Broker Core: `ghcr.io/data-space-core/dsil-idsa-broker/core:latest`
- Broker Fuseki: `ghcr.io/data-space-core/dsil-idsa-broker/fuseki:latest`
- DAPS (Omejdn): `ghcr.io/data-space-core/dsil-omejdn-server/omejdn-server:latest`
- Connector: `ghcr.io/data-space-core/connector/stage:latest`
- Registration UI: `ghcr.io/data-space-core/connector-registration:latest`

If a pull fails with 401/denied, log in:
```
docker login ghcr.io
```
Use a GitHub PAT with `read:packages`.

## Troubleshooting
See `TROUBLESHOOTING.md` for common issues:
- GHCR unauthorized → login with PAT
- Cert/key mismatch → modulus check
- `keytool` missing → install JRE
- Path errors → scripts resolve repo root dynamically
