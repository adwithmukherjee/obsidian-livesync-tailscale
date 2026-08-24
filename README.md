# obsidian livesync on tailscale

my self hosted obsidian sync setup. couchdb only listens on localhost and
tailscale serve makes it available inside my tailnet over https.

no funnel, open ports, vault data, passwords, or tailscale state in this repo.

```text
obsidian -> tailscale serve -> 127.0.0.1:5984 -> couchdb docker volume
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
