#!/bin/sh

set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
template="${repo_dir}/launchd/com.adwithmukherjee.obsidian-livesync-backup.plist.template"
target="${HOME}/Library/LaunchAgents/com.adwithmukherjee.obsidian-livesync-backup.plist"
label="com.adwithmukherjee.obsidian-livesync-backup"
domain="gui/$(id -u)"

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
sed \
  -e "s|__REPO_DIR__|${repo_dir}|g" \
  -e "s|__HOME__|${HOME}|g" \
  "${template}" >"${target}"
chmod 600 "${target}"

launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
launchctl bootstrap "${domain}" "${target}"
launchctl enable "${domain}/${label}"

echo "installed daily backup job: ${label}"
