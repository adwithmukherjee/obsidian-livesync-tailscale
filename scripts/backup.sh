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

backup_dir="${LIVESYNC_BACKUP_DIR:-${HOME}/Library/Application Support/ObsidianLiveSync/backups}"
retention_days="${BACKUP_RETENTION_DAYS:-30}"
volume_name="obsidian-livesync_couchdb-data"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
archive_name="couchdb-${timestamp}.tar.gz"

mkdir -p "${backup_dir}"
chmod 700 "${backup_dir}"

restart_couchdb() {
  docker compose start couchdb >/dev/null 2>&1 || true
}
trap restart_couchdb EXIT INT TERM

echo "stopping couchdb for backup"
docker compose stop -t 60 couchdb >/dev/null

docker run --rm \
  -v "${volume_name}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -czf "/backup/${archive_name}" -C /source .

test -s "${backup_dir}/${archive_name}"
tar -tzf "${backup_dir}/${archive_name}" >/dev/null
chmod 600 "${backup_dir}/${archive_name}"

restart_couchdb
trap - EXIT INT TERM

attempt=0
while [ "${attempt}" -lt 30 ]; do
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
    obsidian-livesync-couchdb 2>/dev/null || true)"
  [ "${health}" = "healthy" ] && break
  attempt=$((attempt + 1))
  sleep 2
done
[ "${health:-}" = "healthy" ]

find "${backup_dir}" -type f -name 'couchdb-*.tar.gz' \
  -mtime "+${retention_days}" -delete

echo "backup ok: ${backup_dir}/${archive_name}"
