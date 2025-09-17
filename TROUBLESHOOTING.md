## Troubleshooting

- GHCR Unauthorized/Denied
  - Symptom: `docker pull ghcr.io/...` fails with `unauthorized`/`denied`.
  - Fix: If images are private, run `docker login ghcr.io` using a GitHub PAT with `read:packages`.
  - Note: Public images should pull without login; preflight warns if it cannot pull anonymously.

- Missing `keytool`
  - Symptom: `keytool` not found during keystore conversion.
  - Fix: Install a JRE, e.g., `sudo apt-get install -y openjdk-17-jre`.

- Docker not accessible
  - Symptom: `docker info` fails or you need `sudo` for docker.
  - Fix: Ensure Docker is running. Add your user to the `docker` group and re-login: `sudo usermod -aG docker "$USER"`.

- Certificate/Key mismatch
  - Symptom: PKCS#12 generation fails or preflight reports mismatch.
  - Fix: Verify you provided the correct public certificate and private key pair. The script checks modulus equality.

- Path assumptions
  - Symptom: Scripts try to read/write at unexpected locations.
  - Fix: Scripts now resolve paths relative to the repo root. Invoke from the repo: `./runner.sh`.

- Re-running after edits
  - Use `./scripts/clean.sh` to stop containers, remove generated keystores, and optionally restore files with git.

