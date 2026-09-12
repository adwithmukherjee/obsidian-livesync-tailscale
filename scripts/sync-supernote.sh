#!/bin/bash

set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

mode="sync"
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  --dry-run) mode="dry-run" ;;
  *) echo "usage: $0 [--check|--dry-run]" >&2; exit 2 ;;
esac

: "${SUPERNOTE_NOTE_DIR:?set SUPERNOTE_NOTE_DIR in .env}"
: "${OBSIDIAN_VAULT_DIR:?set OBSIDIAN_VAULT_DIR in .env}"

if [ ! -d "${SUPERNOTE_NOTE_DIR}" ]; then
  echo "missing supernote notes: ${SUPERNOTE_NOTE_DIR}" >&2
  exit 1
fi

if [ ! -d "${OBSIDIAN_VAULT_DIR}" ]; then
  echo "missing vault: ${OBSIDIAN_VAULT_DIR}" >&2
  exit 1
fi

folders=("20 Classes" "30 Lab")

for folder in "${folders[@]}"; do
  if [ ! -d "${SUPERNOTE_NOTE_DIR}/${folder}" ]; then
    echo "missing supernote folder: ${folder}" >&2
    exit 1
  fi
done

if [ "${mode}" = "check" ]; then
  echo "ok: supernote paths"
  exit 0
fi

lock_dir="${TMPDIR:-/tmp}/obsidian-supernote-copy.lock"
if ! mkdir "${lock_dir}" 2>/dev/null; then
  echo "copy already running"
  exit 0
fi

tmp_file=""
cleanup() {
  [ -z "${tmp_file}" ] || rm -f "${tmp_file}"
  rmdir "${lock_dir}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

copied=0
unchanged=0

copy_folder() {
  local folder="$1"
  local source_root="${SUPERNOTE_NOTE_DIR}/${folder}"
  local target_root="${OBSIDIAN_VAULT_DIR}/${folder}"
  local source_dir source_file relative_dir relative_file target_file

  while IFS= read -r -d '' source_dir; do
    relative_dir="${source_dir#"${source_root}"}"
    [ -z "${relative_dir}" ] || mkdir -p "${target_root}${relative_dir}"
  done < <(find "${source_root}" -type d -print0)

  while IFS= read -r -d '' source_file; do
    relative_file="${source_file#"${source_root}/"}"
    target_file="${target_root}/${relative_file}"

    if [ -f "${target_file}" ] && cmp -s "${source_file}" "${target_file}"; then
      unchanged=$((unchanged + 1))
      continue
    fi

    if [ "${mode}" = "dry-run" ]; then
      echo "copy: ${folder}/${relative_file}"
      copied=$((copied + 1))
      continue
    fi

    mkdir -p "$(dirname -- "${target_file}")"
    tmp_file="${target_file}.supernote-copy.$$"
    cp -p "${source_file}" "${tmp_file}"
    if ! cmp -s "${source_file}" "${tmp_file}"; then
      rm -f "${tmp_file}"
      tmp_file=""
      echo "changed during copy: ${folder}/${relative_file}" >&2
      continue
    fi
    mv -f "${tmp_file}" "${target_file}"
    tmp_file=""
    copied=$((copied + 1))
  done < <(find "${source_root}" -type f -iname '*.note' -print0)
}

for folder in "${folders[@]}"; do
  copy_folder "${folder}"
done

echo "ok: ${copied} copied, ${unchanged} unchanged"
