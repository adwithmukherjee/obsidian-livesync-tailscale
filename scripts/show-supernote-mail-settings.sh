#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}/supernote"

set -a
# shellcheck disable=SC1091
. ./.dbenv
set +a

password="${MP_SMTP_AUTH#supernote:}"

echo "smtp server: mailpit"
echo "port: 1025"
echo "email: supernote@local"
echo "password: ${password}"
echo "encryption: TLS"
echo "test email: me@local"
echo "inbox: http://127.0.0.1:8025"
