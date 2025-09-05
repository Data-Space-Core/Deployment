# Overview

This repository deploys a dataspace stack behind Nginx: an IDS Connector, DAPS (Omejdn), Broker, and supporting UIs. Deployment is idempotent using templates; generated files live under `./.generated`. Secrets and keystores are not committed to the repo.

**Key Commands**
- Run: `./runner.sh`
- Bring up/down: `docker compose up -d` / `docker compose down`

**Quick Links**
- `.env.example` → copy to `.env` and edit
- `nginx.template.conf` → rendered to `./.generated/nginx.conf`
- `conf/config.template.json` → rendered to `./.generated/config.json`

**Endpoints (replace `<host>` with your FQDN)**
- Connector: `https://<host>/connector/api/docs`
- Broker Fuseki: `https://<host>/broker/fuseki/`
- DAPS UI: `https://<host>/`
- Registration API: `https://<host>/connector-registration/register-connector`
- Provider UI: `https://<host>/provider-ui/`
- Consumer UI: `https://<host>/consume/`

**Repository Structure**
- `docker-compose.yml`: service orchestration
- `nginx.template.conf`: Nginx template (rendered at runtime)
- `nginx.development.conf`: legacy dev config (not used in prod)
- `runner.sh`: idempotent bootstrapper (renders templates, starts stack)
- `conf/`: connector config templates and truststore
- `config/`: Omejdn base YAMLs (copied to `.generated/config`)
- `connector_registration/`: Flask service for connector registration
- `scripts/register.sh`: registration helper (writes clients.yml, emits JSON)
- `cert/`: TLS materials and broker keystores (generated, git‑ignored)
- `keys/`: client certs directory (git‑ignored)
- `.generated/`: rendered configs for runtime (git‑ignored)
- `.github/workflows/`: security scans and validation CI

**Included Components**
- IDS Connector, DAPS (Omejdn), Omejdn UI, Data Space Broker
- PostgreSQL (connector persistence)
- Nginx reverse proxy (entrypoint on 80/443)

# Registration Service

The registration API accepts a connector certificate and creates a DAPS client entry. It returns the normalized client certificate file for download.

- Service path: proxied at `https://<host>/connector-registration/`
- Source: `connector_registration/app.py`
- Helper script: `scripts/register.sh`
- Volumes (compose): `/uploads`, `/config`, `/keys`

**Endpoint: POST `/register-connector`**
- Purpose: Register a connector or broker with DAPS and return the stored client certificate file
- Auth: None by default (recommend adding token verification)
- Form fields:
  - `name`: connector name; defaults to `default-connector` if empty
  - `security_profile`: e.g., `idsc:BASE_SECURITY_PROFILE`; defaults if empty
  - `cert_file`: X.509 certificate file (PEM or DER)
- Success response:
  - Content: the stored client certificate file as an attachment
  - Disposition: `attachment; filename=<CLIENT_ID>.cert`
- Error response (JSON):
  - `{"error": "...", "stderr"|"output": "...", "expected_path": "/keys/clients/..."}`

Internal flow:
- The service saves the upload under `/uploads` (10 MB limit, sanitized name)
- Calls `/scripts/register.sh <name> <security_profile> <cert_file> --config-dir /config --keys-dir /keys`
- Parses script JSON from stdout (final line) to locate the generated `client_cert` path
- Streams that file back if present

Script behavior (`scripts/register.sh`):
- Computes `client_id` from certificate SKI/AKI, appends an entry to `/config/clients.yml`
- Stores the normalized cert as `/keys/clients/<client_id>.cert`
- Prints legacy log and a final JSON line like: `{"client_id":"...","client_name":"...","client_cert":"/keys/clients/<id>.cert"}`

# Services

Defined in `docker-compose.yml`:
- `nginx`: public gateway on `80`/`443`; mounts `./.generated/nginx.conf` and `./cert`
- `broker-core`: broker core; internal only
- `broker-fuseki`: SPARQL endpoint; internal only
- `omejdn-server`: DAPS server; mounts `./.generated/config` and `./keys`
- `omejdn-ui`: DAPS admin UI; proxied at root (`/`)
- `connector-database`: Postgres; internal only
- `connector`: IDS connector; proxied under `/connector/`
- `connector-registration`: Flask registration API; proxied under `/connector-registration/`
- `connector-registration-user-interface`: UI for registration; proxied under `/connector-registration-user-interface/`
- `provider-ui`: provider UI; proxied under `/provider-ui/`
- `consumer-ui`: consumer UI; proxied under `/consume/`

# Configuration

- `.env`: copy from `.env.example` and adjust
  - `DOMAIN`, `OMEJDN_PATH`, `ALLOWED_ORIGIN`
  - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
  - `ADMIN_USERNAME`, `ADMIN_PASSWORD` (Omejdn admin)
- Templates
  - `nginx.template.conf` → `./.generated/nginx.conf`
  - `conf/config.template.json` → `./.generated/config.json`
- Generated
  - `./.generated/config/*.yml` → used by `omejdn-server`
  - `./conf/default-connector-keystore.p12`, `./cert/isstbroker-keystore.{p12,jks}` → created by `runner.sh`

# Install

Prerequisites:
- FQDN DNS record, Docker, Docker Compose
- TLS materials for the FQDN: private key, server cert, chained fullchain

Steps:
- Optionally set variables in `.env`
- Run `./runner.sh` and provide FQDN and TLS paths when prompted
- The script renders configs, generates keystores, and runs `docker compose up -d`

# Security & Ops

- Secrets and keystores are git‑ignored; do not commit them
- DB is internal only; Nginx is the only public entrypoint
- CORS limited via `ALLOWED_ORIGIN`; adjust as needed
- CI: gitleaks, Trivy, hadolint, bandit/pip‑audit, compose validation under `.github/workflows/`

# Development

- Local iteration on the registration service: edit `connector_registration/` and recreate the container
- Dev Nginx config: `nginx.development.conf` (for experimentation only)

# Troubleshooting

- Rendered Nginx config: `./.generated/nginx.conf`
- Omejdn config and clients: `./.generated/config/`
- Registration uploads: `./upload/` (host), `/uploads` (container)
- Check logs: `docker compose logs -f <service>`
