#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
target="${repo_dir}/supernote/.uploadenv"
account="${1:-}"

if [ -z "${account}" ]; then
  printf "supernote email: " >&2
  IFS= read -r account
fi

printf "supernote password: " >&2
stty -echo
trap 'stty echo' EXIT INT TERM
IFS= read -r password
stty echo
trap - EXIT INT TERM
printf "\n" >&2

password_b64="$(printf %s "${password}" | base64 | tr -d '\n')"
tmp="${target}.tmp.$$"
umask 077
{
  printf 'SUPERNOTE_ACCOUNT=%s\n' "${account}"
  printf 'SUPERNOTE_PASSWORD_B64=%s\n' "${password_b64}"
  printf 'SUPERNOTE_COUNTRY_CODE=1\n'
} >"${tmp}"
mv "${tmp}" "${target}"

echo "saved supernote/.uploadenv"
