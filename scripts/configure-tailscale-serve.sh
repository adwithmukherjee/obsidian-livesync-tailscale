#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

if command -v tailscale >/dev/null 2>&1; then
  tailscale_cli="$(command -v tailscale)"
elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
  tailscale_cli=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  export TAILSCALE_BE_CLI=1
else
  echo "Tailscale CLI not found." >&2
  exit 1
fi

"${tailscale_cli}" status >/dev/null
"${tailscale_cli}" serve --bg --yes "http://127.0.0.1:${COUCHDB_PORT:-5984}"
"${tailscale_cli}" serve status
