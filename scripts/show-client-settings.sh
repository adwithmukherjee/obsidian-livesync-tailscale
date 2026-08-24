#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}"

set -a
# shellcheck disable=SC1091
. ./.env
set +a

if command -v tailscale >/dev/null 2>&1; then
  tailscale_cli="$(command -v tailscale)"
elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
  tailscale_cli=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  export TAILSCALE_BE_CLI=1
else
  echo "Tailscale CLI not found." >&2
  exit 1
fi

dns_name="$("${tailscale_cli}" status --json | \
  sed -n 's/.*"DNSName": "\([^"]*\)".*/\1/p' | head -1 | sed 's/\.$//')"

printf 'URI: https://%s\n' "${dns_name}"
printf 'Username: %s\n' "${COUCHDB_USER}"
printf 'Password: %s\n' "${COUCHDB_PASSWORD}"
printf 'Database: %s\n' "${COUCHDB_DATABASE}"
printf '%s\n' 'End-to-end passphrase: choose one in LiveSync and store it in your password manager'
