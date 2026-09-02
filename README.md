# obsidian livesync on tailscale

my self hosted obsidian and supernote sync setup. couchdb only listens on
localhost and tailscale serve makes it available inside my tailnet over https.

the supernote endpoint uses funnel on port `8443` so the manta can reach it
away from home. couchdb stays private. no vault data, passwords, or tailscale
state in this repo.

```text
obsidian -> tailscale serve -> 127.0.0.1:5984 -> couchdb docker volume
manta -> tailscale funnel :8443 -> private cloud -> vault -> livesync
```

## setup

needs docker, tailscale, and magicdns.

```sh
./scripts/bootstrap.sh
./scripts/verify.sh
./scripts/configure-tailscale-serve.sh
```

`bootstrap.sh` makes a gitignored `.env` with a random couchdb password.

to get the values for the livesync plugin:

```sh
./scripts/show-client-settings.sh
```

pick a separate end to end encryption password in livesync and save it in a
password manager. couchdb does not need it.

## adding devices

1. back up the original vault
2. install the self-hosted livesync community plugin
3. enter the uri, username, password, and database from the script above
4. use the same encryption password on every device
5. make sure normal notes sync before trying hidden file sync

on iphone, keep tailscale on and give obsidian time to finish syncing before
closing it. dont use icloud, obsidian sync, or another sync tool on the same
vault.

## backups

run one now:

```sh
./scripts/backup.sh
```

backups go in `~/Library/Application Support/ObsidianLiveSync/backups`. couchdb
stops briefly so the archive is consistent. old backups are kept for 30 days.

install the daily 3:15am job:

```sh
./scripts/install-backup-launch-agent.sh
```

docker desktop needs to be running and the user needs to be logged in. copies
on a second disk are still a good idea.

## supernote copy

the private cloud stack lives in `supernote/`. it uses the current official
images. on apple silicon, the two supernote images run through docker's amd64
emulation.

start the local service:

```sh
./scripts/bootstrap-supernote.sh
./scripts/verify-supernote.sh
```

registration mail stays local. use these values in the email server form:

```sh
./scripts/show-supernote-mail-settings.sh
```

open `http://127.0.0.1:8025` to read codes.

finish email setup and create the admin account before making it public. then:

```sh
./scripts/configure-supernote-funnel.sh
```

the public address is the tailscale dns name with port `8443`. no domain or
router port forwarding is needed. the mac and docker desktop must be awake.
the local proxy on `19073` removes a duplicate port from funnel's forwarded
hostname before requests reach supernote.

the docker copy job moves handwritten notes out of private cloud storage. it only
reads `Note/Classes` and `Note/Lab`, only copies `.note` files, and never deletes
anything from the vault.

set these in `supernote/.env`:

```sh
SUPERNOTE_NOTE_DIR=./supernote_data/account/Supernote/Note
OBSIDIAN_VAULT_DIR=/Users/me/Documents/Obsidian/Notes
SUPERNOTE_COPY_INTERVAL=300
```

start it:

```sh
docker compose -f supernote/compose.yaml up -d obsidian-copy
```

the supernote copy wins when the same `.note` file differs. writes are atomic.
the background job runs every five minutes by default. livesync handles the
copied files after that.

PDFs in vault `Classes` and `Lab` can go the other way. Markdown files are
rendered to PDF first. existing remote filenames are left alone.

```sh
./scripts/configure-supernote-upload.sh your@email.com
docker compose -f supernote/compose.yaml --profile copy up -d --build supernote-upload
```

the first upload run records a deletion baseline. after that, a file missing
from private cloud for one check is moved from the vault into
`.trash/supernote`. this only applies inside `Classes` and `Lab`. folders and
`.mark` sidecars are never deleted directly.

renaming or moving a tracked file on the Manta moves the matching vault file.
for rendered markdown, the `.md` source follows the renamed PDF. the Manta path
wins.

## useful commands

```sh
docker compose ps
docker compose logs --tail=100 couchdb
docker compose restart couchdb
./scripts/verify.sh
```

disable the endpoint with `tailscale serve reset`.

the couchdb settings are based on the upstream
[self-hosted livesync](https://github.com/vrtmrz/obsidian-livesync) setup.
