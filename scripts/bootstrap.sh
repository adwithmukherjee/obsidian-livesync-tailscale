#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
env_file="${repo_dir}/.env"

if [ ! -f "${env_file}" ]; then
  umask 077
  password="$(openssl rand -hex 32)"
  {
    printf '%s\n' 'COUCHDB_USER=obsidian'
    printf '%s\n' "COUCHDB_PASSWORD=${password}"
    printf '%s\n' 'COUCHDB_DATABASE=obsidiannotes'
    printf '%s\n' 'COUCHDB_PORT=5984'
    printf '%s\n' 'BACKUP_RETENTION_DAYS=30'
  } >"${env_file}"
  echo "created ${env_file} with a random couchdb password"
else
  echo "using existing ${env_file}"
fi

chmod 600 "${env_file}"
cd "${repo_dir}"
docker compose up -d --build

echo "waiting for couchdb init"
attempt=0
while [ "${attempt}" -lt 60 ]; do
  init_status="$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' obsidian-livesync-init 2>/dev/null || true)"
  if [ "${init_status}" = "exited 0" ]; then
    echo "couchdb is ready"
    exit 0
  fi
  case "${init_status}" in
    exited\ *)
      echo "init failed: ${init_status}" >&2
      docker logs obsidian-livesync-init >&2
      exit 1
      ;;
  esac
  attempt=$((attempt + 1))
  sleep 2
done

echo "timed out waiting for init" >&2
docker compose ps >&2
exit 1
