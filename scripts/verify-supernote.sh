#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}/supernote"

set -a
# shellcheck disable=SC1091
. ./.env
# shellcheck disable=SC1091
. ./.dbenv
set +a

docker compose ps --status running --services | grep -qx mariadb
docker compose ps --status running --services | grep -qx redis
docker compose ps --status running --services | grep -qx notelib
docker compose ps --status running --services | grep -qx mailpit
docker compose ps --status running --services | grep -qx supernote-service
docker compose ps --status running --services | grep -qx funnel-proxy

docker compose exec -T supernote-service sh -c \
  'keytool -list -keystore "$JAVA_HOME/jre/lib/security/cacerts" -storepass changeit -alias local-mailpit' \
  >/dev/null

docker compose exec -T mariadb mariadb \
  -u"${MYSQL_USER}" \
  -p"${MYSQL_PASSWORD}" \
  "${MYSQL_DATABASE}" \
  -e 'DESCRIBE b_dictionary' >/dev/null

status="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SUPERNOTE_HTTP_PORT:-19072}/")"
case "${status}" in
  200|301|302) ;;
  *) echo "bad supernote http status: ${status}" >&2; exit 1 ;;
esac

proxy_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  -H 'Host: private-cloud.example:8443' \
  -H 'X-Forwarded-Host: private-cloud.example:8443' \
  "http://127.0.0.1:${SUPERNOTE_FUNNEL_PROXY_PORT:-19073}/api/file/query/server")"
[ "${proxy_status}" = "200" ] || { echo "bad funnel proxy status: ${proxy_status}" >&2; exit 1; }

echo "ok: containers, database, local mail, local http, funnel proxy"
