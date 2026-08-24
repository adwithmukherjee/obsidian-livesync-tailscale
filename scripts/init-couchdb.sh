#!/bin/sh

set -eu

host="${COUCHDB_INTERNAL_URL:-http://couchdb:5984}"
username="${COUCHDB_USER:?COUCHDB_USER is required}"
password="${COUCHDB_PASSWORD:?COUCHDB_PASSWORD is required}"
database="${COUCHDB_DATABASE:-obsidiannotes}"
node="${COUCHDB_NODE:-_local}"

echo "waiting for couchdb"
until curl -fsS "${host}/_up" 2>/dev/null | grep -q '"status":"ok"'; do
  sleep 2
done

curl -fsS -X POST "${host}/_cluster_setup" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"enable_single_node\",\"username\":\"${username}\",\"password\":\"${password}\",\"bind_address\":\"0.0.0.0\",\"port\":5984,\"singlenode\":true}" \
  --user "${username}:${password}" >/dev/null

put_config() {
  section="$1"
  key="$2"
  value="$3"
  curl -fsS -X PUT "${host}/_node/${node}/_config/${section}/${key}" \
    -H "Content-Type: application/json" \
    -d "${value}" \
    --user "${username}:${password}" >/dev/null
}

put_config chttpd require_valid_user '"true"'
put_config chttpd_auth require_valid_user '"true"'
put_config httpd WWW-Authenticate '"Basic realm=\"couchdb\""'
put_config httpd enable_cors '"true"'
put_config chttpd enable_cors '"true"'
put_config chttpd max_http_request_size '"4294967296"'
put_config couchdb max_document_size '"50000000"'
put_config cors credentials '"true"'
put_config cors origins '"app://obsidian.md,capacitor://localhost,http://localhost"'

status="$(curl -sS -o /dev/null -w '%{http_code}' \
  --user "${username}:${password}" "${host}/${database}")"
if [ "${status}" = "404" ]; then
  curl -fsS -X PUT --user "${username}:${password}" \
    "${host}/${database}" >/dev/null
elif [ "${status}" != "200" ]; then
  echo "unexpected database status: ${status}" >&2
  exit 1
fi

echo "couchdb ready: ${database}"
