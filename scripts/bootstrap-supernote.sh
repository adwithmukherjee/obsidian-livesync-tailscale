#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cloud_dir="${repo_dir}/supernote"
cd "${cloud_dir}"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "made supernote/.env"
fi

if [ ! -f .dbenv ]; then
  umask 077
  mysql_root_password="$(openssl rand -hex 16)"
  mysql_password="$(openssl rand -hex 16)"
  redis_password="$(openssl rand -hex 16)"
  {
    echo "MYSQL_ROOT_PASSWORD=${mysql_root_password}"
    echo "MYSQL_DATABASE=supernotedb"
    echo "MYSQL_USER=enote"
    echo "MYSQL_PASSWORD=${mysql_password}"
    echo "REDIS_PASSWORD=${redis_password}"
    echo "MP_SMTP_AUTH=supernote:$(openssl rand -hex 16)"
  } >.dbenv
  echo "made supernote/.dbenv"
fi

if ! grep -q '^MP_SMTP_AUTH=' .dbenv; then
  echo "MP_SMTP_AUTH=supernote:$(openssl rand -hex 16)" >>.dbenv
fi

mkdir -p \
  sndata/db_data \
  sndata/config/mysql/conf.d \
  sndata/redis_data \
  sndata/recycle \
  sndata/logs/cloud \
  sndata/logs/app \
  sndata/logs/web \
  sndata/convert \
  sndata/mailpit/data \
  sndata/mailpit/cert \
  supernote_data

if [ ! -f sndata/mailpit/cert/mailpit.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout sndata/mailpit/cert/mailpit.key \
    -out sndata/mailpit/cert/mailpit.crt \
    -sha256 -days 3650 \
    -subj '/CN=mailpit' \
    -addext 'subjectAltName=DNS:mailpit' >/dev/null 2>&1
  chmod 644 sndata/mailpit/cert/mailpit.crt sndata/mailpit/cert/mailpit.key
fi

sql_url="https://supernote-private-cloud.supernote.com/cloud/supernotedb.sql"
hash_url="${sql_url}.sha256"
sql_tmp="supernotedb.sql.tmp"

curl -fsSL "${sql_url}" -o "${sql_tmp}"
expected_hash="$(curl -fsSL "${hash_url}" | awk '{print $1}')"
actual_hash="$(shasum -a 256 "${sql_tmp}" | awk '{print $1}')"

if [ "${actual_hash}" != "${expected_hash}" ]; then
  rm -f "${sql_tmp}"
  echo "bad supernotedb.sql checksum" >&2
  exit 1
fi

mv "${sql_tmp}" supernotedb.sql
docker compose pull --ignore-buildable
docker compose up -d --build

echo "supernote private cloud starting on http://127.0.0.1:19072"
