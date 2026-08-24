#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}"

set -a
# shellcheck disable=SC1091
. ./.env
set +a

authenticated_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  --user "${COUCHDB_USER}:${COUCHDB_PASSWORD}" \
  "http://127.0.0.1:${COUCHDB_PORT}/_up")"
unauthenticated_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:${COUCHDB_PORT}/${COUCHDB_DATABASE}")"
database_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  --user "${COUCHDB_USER}:${COUCHDB_PASSWORD}" \
  "http://127.0.0.1:${COUCHDB_PORT}/${COUCHDB_DATABASE}")"
cors_headers="$(curl -sS -i -X OPTIONS \
  -H 'Origin: app://obsidian.md' \
  -H 'Access-Control-Request-Method: GET' \
  "http://127.0.0.1:${COUCHDB_PORT}/_up")"

[ "${authenticated_status}" = "200" ]
[ "${unauthenticated_status}" = "401" ]
[ "${database_status}" = "200" ]
printf '%s' "${cors_headers}" | grep -qi '^access-control-allow-origin: app://obsidian.md'

docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
  obsidian-livesync-couchdb | grep -qx healthy

echo "ok: health, auth, database, cors, container"
