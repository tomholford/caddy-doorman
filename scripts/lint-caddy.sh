#!/usr/bin/env bash
#
# Validate examples/Caddyfile against a custom Caddy binary containing the
# caddy-doorman plugin stack.
#
# The binary is fetched from the official Caddy download API, so no Go
# toolchain or xcaddy is required. It is cached at ./caddy-custom (gitignored).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CADDY_BIN="${ROOT_DIR}/caddy-custom"

# Modules baked into the image — keep in sync with the Dockerfile.
MODULES=(
  pkg.jsn.cam/caddy-defender
  github.com/mholt/caddy-ratelimit
  github.com/caddy-dns/namecheap
  github.com/caddy-dns/cloudflare
  github.com/monobilisim/caddy-ip-list
)

if [ ! -x "$CADDY_BIN" ]; then
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
  esac
  url="https://caddyserver.com/api/download?os=${os}&arch=${arch}"
  for m in "${MODULES[@]}"; do
    url+="&p=${m//\//%2F}"
  done
  echo "Fetching custom Caddy (${os}/${arch}) from caddyserver.com ..."
  curl -fsSL --retry 3 -o "$CADDY_BIN" "$url"
  chmod +x "$CADDY_BIN"
fi

echo "Using: $("$CADDY_BIN" version)"

# Dummy secrets so {env.*} placeholders resolve during validation.
# Cloudflare API tokens are expected to be 40 chars.
ENV_FILE="$(mktemp)"
trap 'rm -f "$ENV_FILE"' EXIT
cat > "$ENV_FILE" <<'EOF'
CLOUDFLARE_API_TOKEN=0123456789abcdef0123456789abcdef01234567
NAMECHEAP_API_KEY=dummy_namecheap_api_key
NAMECHEAP_API_USER=dummyuser
EOF

echo "Validating examples/Caddyfile ..."
"$CADDY_BIN" validate \
  --config "${ROOT_DIR}/examples/Caddyfile" \
  --adapter caddyfile \
  --envfile "$ENV_FILE"
echo "OK"
