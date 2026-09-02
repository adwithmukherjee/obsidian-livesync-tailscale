#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
template="${repo_dir}/launchd/com.adwithmukherjee.obsidian-supernote-copy.plist.template"
target="${HOME}/Library/LaunchAgents/com.adwithmukherjee.obsidian-supernote-copy.plist"
label="com.adwithmukherjee.obsidian-supernote-copy"
domain="gui/$(id -u)"

cd "${repo_dir}"
set -a
# shellcheck disable=SC1091
. ./.env
set +a

interval="${SUPERNOTE_COPY_INTERVAL:-300}"
case "${interval}" in
  ''|*[!0-9]*) echo "SUPERNOTE_COPY_INTERVAL must be seconds" >&2; exit 1 ;;
esac
[ "${interval}" -gt 0 ] || { echo "SUPERNOTE_COPY_INTERVAL must be greater than zero" >&2; exit 1; }

./scripts/sync-supernote.sh --check

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
sed \
  -e "s|__REPO_DIR__|${repo_dir}|g" \
  -e "s|__HOME__|${HOME}|g" \
  -e "s|__INTERVAL__|${interval}|g" \
  "${template}" >"${target}"
chmod 600 "${target}"

launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
launchctl bootstrap "${domain}" "${target}"
launchctl enable "${domain}/${label}"

echo "installed supernote copy job: ${label}"
