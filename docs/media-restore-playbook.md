# Media restore playbook

[Services](services.md) · [Operations](operations.md) · [Secrets](../secrets/README.md)

This is the operator procedure for restoring the media stack from the
`my.media.backup` restic repository. Use the
[restore drill](services.md#media-state-backups) to rehearse the path against a
throwaway VM before relying on it. The automatic
`media-backup-restore.service` restores the **latest** snapshot; manual restic
commands are required when that snapshot is bad or SOPS is unavailable.

## What the backup contains

- PostgreSQL dumps of `radarr`, `sonarr`, `prowlarr`, and `seerr`.
- Consistent SQLite copies of Jellyfin's `data/*.db`, plus Jellyfin config,
  metadata, and plugins.
- Decypharr's `db/` and `usenet/` state.
- Seerr's `settings.json`, the Radarr/Sonarr/Prowlarr config directories, the
  `/data/media` and `/data/downloads` symlink trees, and the host SOPS key.

It is **not** a media archive. The media paths are symlinks to Decypharr's
upstream releases; if the provider has expired the release, the library records
restore but playback still fails. The bucket also contains the host age
identity, so protect the B2 account and application key as sensitive data.

## Recovery kit

Keep these outside `teeny` and outside the repository:

- The `sam` age identity. It can decrypt
  `secrets/media-backup/secrets.yaml`; this is the preferred recovery identity.
- The `teeny` system age identity, if you want to keep the existing SOPS
  recipient. The backup contains `/var/lib/sops-nix/key.txt`, but repository
  access is needed before it can be read.
- The B2 account ID, B2 application key, and restic repository password. These
  are the fallback if the `sam` and `teeny` identities are lost.
- A checkout of this repository, access to the deploy account or host console,
  the B2 bucket name and path, and the B2 account console.

Do not store the only copy of the B2 or restic credentials in SOPS on `teeny`.
A complete wipe removes the only key that can decrypt them. If the `sam` key,
the `teeny` key, and the offline B2/restic values are all lost, the repository
is unreadable.

## Choose the path

| Situation                                                | Procedure                                              |
| -------------------------------------------------------- | ------------------------------------------------------ |
| `teeny` is running but media state is lost or corrupted  | [In-place restore](#in-place-restore-on-teeny)         |
| Replacing `teeny` and keeping its age identity           | [Recover the old key](#recover-the-original-teeny-key) |
| Replacing `teeny` with a new age identity                | [Rekey first](#rekey-to-a-new-host-identity)           |
| Only a few files are needed                              | [Partial restore](#partial-restore)                    |
| The latest snapshot is bad or SOPS cannot start the unit | [Manual restore](#manual-full-restore)                 |

## Before any restore

The examples use `/root/media-recovery` on the target. Create that root-only
directory from a machine with the `sam` identity, or from the target with its
system identity (set `SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt`):

```bash
umask 077
install -d -m 0700 /root/media-recovery
sops --decrypt --extract '["b2"]["account-id"]' secrets/media-backup/secrets.yaml > /root/media-recovery/b2-account-id
sops --decrypt --extract '["b2"]["application-key"]' secrets/media-backup/secrets.yaml > /root/media-recovery/b2-application-key
sops --decrypt --extract '["restic"]["password"]' secrets/media-backup/secrets.yaml > /root/media-recovery/restic-password
```

If you extract on a trusted machine with a non-root account, use a protected
directory under your home and copy the three files to `/root/media-recovery` on
the target. Remove the directory after the restore.

1. Confirm the latest snapshot exists and is the one you expect. On a trusted
   machine with the `sam` identity, or on the host with its system identity:

   ```bash
   export RESTIC_REPOSITORY='b2:swillis-media-backups:teeny'
   export RESTIC_PASSWORD="$(cat /root/media-recovery/restic-password)"
   export B2_ACCOUNT_ID="$(cat /root/media-recovery/b2-account-id)"
   export B2_ACCOUNT_KEY="$(cat /root/media-recovery/b2-application-key)"
   nix shell nixpkgs#restic -c restic snapshots --host media-stack --tag media-stack
   ```

   The repository password and B2 values can be extracted from SOPS with the
   `sam` key, or copied from `teeny` before a rebuild. The
   [drill instructions](services.md#media-state-backups) show the extraction
   commands. Keep them in a root-only directory and remove them afterwards.

2. Check the B2 download cap. A full restore downloads about 1.5 GiB. A cap or
   transaction limit produces `Class B` errors from B2 and the restore fails
   before changing the host.

3. Confirm the target has enough free disk for the restored state and
   PostgreSQL. The drill uses a 20 GiB disk; the current snapshot is about
   1.4 GiB / 9,000 files.

4. If the current host still has readable state you want to keep, take a fresh
   backup before restoring. Do not take a backup of a host whose database or
   media state is already corrupt just to have a "latest" snapshot.

5. Stop `media-backup.timer` before restoring and leave it stopped until the
   restored state is verified. A backup that runs after data loss can become
   the latest snapshot.

6. Decide the SOPS key strategy before activating a replacement host. The
   automatic restore includes `/var/lib/sops-nix/key.txt`; on a new host that
   can overwrite the new identity with the old one.

## In-place restore on teeny

Use this when `teeny` still boots and its SOPS identity still decrypts the
repository credentials.

```bash
ssh teeny
sudo systemctl status media-backup.service
sudo systemctl list-timers media-backup.timer
sudo journalctl -u media-backup.service -n 50 --no-pager
```

Then stop the timer and start the restore unit:

```bash
sudo systemctl stop media-backup.timer
sudo systemctl start media-backup-restore.service
sudo systemctl status media-backup-restore.service
sudo journalctl -u media-backup-restore.service -n 100 --no-pager
sudo reboot
```

The unit stops Jellyfin, the three \*arr services, Seerr, and Decypharr; restores
the latest snapshot; recreates the PostgreSQL databases from the dumps; installs
the staged Jellyfin databases and Decypharr state with service ownership;
reinstalls the SOPS secrets; and starts the services. Reboot afterwards so
`nixflix` reconciles setup units that ran before the restore.

See [Verify the restore](#verify-the-restore). If the unit fails, read the
journal before retrying; the state may be partially restored.

## Replacement host

Follow the [remote deployment bootstrap](operations.md#remote-deployment) for
the new machine. Do not enable a second timer against the same repository path
while recovering: the automatic unit uses the `media-stack` host label and
would mix snapshots if both hosts back up to the same path.

### Recover the original teeny key

This is the simplest replacement path and keeps the existing SOPS recipient.

1. On a trusted machine that has the `sam` identity, create a protected
   credential directory and list snapshots:

   ```bash
   nix develop
   umask 077
   install -d -m 0700 "$HOME/media-recovery"
   sops --decrypt --extract '["b2"]["account-id"]' secrets/media-backup/secrets.yaml > "$HOME/media-recovery/b2-account-id"
   sops --decrypt --extract '["b2"]["application-key"]' secrets/media-backup/secrets.yaml > "$HOME/media-recovery/b2-application-key"
   sops --decrypt --extract '["restic"]["password"]' secrets/media-backup/secrets.yaml > "$HOME/media-recovery/restic-password"
   ```

2. Restore only the old host key from the snapshot:

   ```bash
   export RESTIC_REPOSITORY='b2:swillis-media-backups:teeny'
   export RESTIC_PASSWORD="$(cat "$HOME/media-recovery/restic-password")"
   export B2_ACCOUNT_ID="$(cat "$HOME/media-recovery/b2-account-id")"
   export B2_ACCOUNT_KEY="$(cat "$HOME/media-recovery/b2-application-key")"
   nix shell nixpkgs#restic -c restic snapshots --host media-stack --tag media-stack
   nix shell nixpkgs#restic -c restic restore SNAPSHOT_ID \
     --target /tmp/teeny-key \
     --include /var/lib/sops-nix/key.txt
   ```

3. Install the recovered identity on the new host and verify its public
   recipient matches the `teeny` recipient in `.sops.yaml`:

   ```bash
   sudo install -d -m 0700 /var/lib/sops-nix
   sudo install -m 0600 /tmp/teeny-key/var/lib/sops-nix/key.txt /var/lib/sops-nix/key.txt
   sudo nix shell nixpkgs#age -c age-keygen -y /var/lib/sops-nix/key.txt
   ```

4. Deploy the host with the normal `teeny` configuration. The old system
   identity now decrypts `secrets/media-backup`, so the automatic restore unit
   can start. Disable the backup timer for this first deployment as described
   under [Deploy and restore](#deploy-and-restore), then run the
   [in-place restore](#in-place-restore-on-teeny) and reboot.

Remove `/tmp/teeny-key` after installing the key. Do not commit or copy the
private identity into the repository or a Nix store path.

### Rekey to a new host identity

Use this when the old `teeny` identity is intentionally retired. This changes
the SOPS recipient set and the new host's key must not be overwritten by the
snapshot's old key.

1. Install NixOS and let it generate the new `/var/lib/sops-nix/key.txt` (or
   pre-provision it as described in the [secret guide](../secrets/README.md)).
   Record only the public recipient:

   ```bash
   sudo nix shell nixpkgs#age -c age-keygen -y /var/lib/sops-nix/key.txt
   ```

2. On the trusted machine with the `sam` identity, add that public recipient to
   the `secrets/media-backup/secrets.yaml` creation rule in `.sops.yaml`, then
   re-encrypt the file:

   ```bash
   sops updatekeys secrets/media-backup/secrets.yaml
   ```

3. Deploy the normal host configuration once so SOPS and the service
   definitions exist. Disable the backup timer for this deployment as described
   under [Deploy and restore](#deploy-and-restore); the empty host must not
   create a "latest" snapshot.

4. For the restore, prevent the old snapshot key from replacing the new host
   key. Either set `my.media.backup.sopsKeyFile = null;` in the host
   configuration for the restore deployment, or use the
   [manual restore](#manual-full-restore) and do not include
   `/var/lib/sops-nix/key.txt` in the restic `--include` list. With the option
   set to `null`, the automatic restore still handles the databases, Jellyfin,
   Decypharr, and the symlink trees, but not the host identity.

5. After the restore succeeds, remove the temporary `sopsKeyFile = null`,
   redeploy, and take a fresh backup so the new host identity is protected by
   the backup. Verify the new recipient can decrypt the SOPS file before
   removing the old `teeny` recipient.

### Deploy and restore

Deploy the same media host configuration with `my.media.backup` enabled and the
same repository. Use the approved deployment path:

```bash
nix run .#deploy -- .#teeny
```

Alternatively, on the host after its initial bootstrap:

```bash
sudo nixos-rebuild switch --flake .#teeny
```

Wait for `postgresql.service`, `postgresql-setup.service`, and
`sops-install-secrets.service`, then run the
[in-place restore](#in-place-restore-on-teeny). On any replacement host, disable
its backup timer for the first deployment and leave it disabled until the
restore is verified:

```nix
systemd.timers.media-backup.wantedBy = lib.mkForce [ ];
```

A temporary target must stay disabled. The `media-backup` secret group is
currently encrypted to `sam` and `teeny`; `staging-vm` cannot decrypt it unless
you add its recipient and rekey, or provide temporary credential files outside
the Nix store. After verification, remove the override and redeploy; the next
backup protects the restored host identity.

## Manual full restore

Use this when the automatic service cannot start because SOPS is unavailable,
or when you need a snapshot other than the latest. Run the restore in a root
shell on the target with the repository credentials available.

```bash
sudo -s
export RESTIC_REPOSITORY='b2:swillis-media-backups:teeny'
export RESTIC_PASSWORD="$(cat /root/media-recovery/restic-password)"
export B2_ACCOUNT_ID="$(cat /root/media-recovery/b2-account-id)"
export B2_ACCOUNT_KEY="$(cat /root/media-recovery/b2-application-key)"
nix shell nixpkgs#restic -c restic snapshots --host media-stack --tag media-stack
```

Stop the media services, then restore the snapshot's state. Replace
`SNAPSHOT_ID` with the ID from `restic snapshots`.

```bash
systemctl stop jellyfin radarr sonarr prowlarr seerr decypharr 2>/dev/null || true

# Omit the key include when keeping a new host identity.
nix shell nixpkgs#restic -c restic restore SNAPSHOT_ID \
  --target / \
  --include /run/media-backup \
  --include /var/lib/jellyfin \
  --include /var/lib/seerr \
  --include /var/lib/radarr \
  --include /var/lib/sonarr \
  --include /var/lib/prowlarr \
  --include /var/lib/decypharr \
  --include /data/media \
  --include /data/downloads \
  --include /var/lib/sops-nix/key.txt
```

Install the consistent Jellyfin databases and Decypharr state with the same
ownership the service uses:

```bash
install -d -m 0755 -o jellyfin -g media /var/lib/jellyfin/data
for db in /run/media-backup/jellyfin/*.db; do
  [ -e "$db" ] || continue
  install -m 0640 -o jellyfin -g media "$db" /var/lib/jellyfin/data/
done

install -d -m 0750 -o decypharr -g media /var/lib/decypharr
rm -rf /var/lib/decypharr/db /var/lib/decypharr/usenet
for sub in db usenet; do
  [ -d "/run/media-backup/decypharr/$sub" ] || continue
  cp -a "/run/media-backup/decypharr/$sub" /var/lib/decypharr/
  chown -R decypharr:media "/var/lib/decypharr/$sub"
done
```

Recreate the PostgreSQL databases from the dumps. The `--role` option keeps
ownership aligned with the `ensureUsers` declarations:

```bash
nix shell nixpkgs#postgresql -c bash -c '
  for db in radarr sonarr prowlarr seerr; do
    runuser -u postgres -- dropdb --force --if-exists "$db"
    runuser -u postgres -- createdb --owner="$db" "$db"
    runuser -u postgres -- pg_restore \
      --dbname="$db" \
      --no-owner \
      --role="$db" \
      --exit-on-error \
      < "/run/media-backup/postgres/$db.dump"
  done
'
```

If you restored the host identity, reinstall the SOPS secrets before starting
services. If you are keeping a new host identity, do not overwrite it; start the
services and let the existing SOPS activation handle the secrets.

```bash
systemctl start sops-install-secrets.service 2>/dev/null || true
systemctl start radarr sonarr prowlarr decypharr seerr jellyfin 2>/dev/null || true
reboot
```

The manual path does not run the `jellyfin-*` and `seerr-setup` reconciliation
units. The reboot lets `nixflix` run them; verify the result rather than
assuming they succeeded.

## Partial restore

To inspect or recover one application without stopping the whole stack, restore
to a temporary directory and copy only the required files:

```bash
nix shell nixpkgs#restic -c restic restore SNAPSHOT_ID \
  --target /tmp/media-partial \
  --include /var/lib/radarr
```

Stop the affected service before replacing its directory. Preserve ownership
and do not copy a live SQLite database from a running Jellyfin; use the staged
`.backup` copy under `/run/media-backup/jellyfin`.

## Verify the restore

Start with the services and the next backup:

```bash
systemctl status media-backup.timer media-backup.service
systemctl list-timers media-backup.timer
journalctl -u media-backup-restore.service -n 100 --no-pager
```

Check Jellyfin's database integrity and the service ownership:

```bash
nix shell nixpkgs#sqlite -c sqlite3 /var/lib/jellyfin/data/jellyfin.db \
  'PRAGMA integrity_check;'
nix shell nixpkgs#sqlite -c sqlite3 /var/lib/jellyfin/data/jellyfin.db \
  "SELECT count(*) FROM sqlite_master WHERE type = 'table';"
stat -c '%u:%g %n' /var/lib/jellyfin/data/jellyfin.db
```

The current snapshot should report `ok`, more than ten tables, and owner
`146:169`. Check the application databases and the key \*arr tables:

```bash
nix shell nixpkgs#postgresql -c bash -c '
  for db in radarr sonarr prowlarr seerr; do
    echo "$db: $(runuser -u postgres -- psql -d "$db" -tAc \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema = '\''public'\''")"
  done
  runuser -u postgres -- psql -d radarr -tAc "SELECT count(*) FROM \"Movies\""
  runuser -u postgres -- psql -d sonarr -tAc "SELECT count(*) FROM \"Series\""
  runuser -u postgres -- psql -d prowlarr -tAc "SELECT count(*) FROM \"Indexers\""
'
```

Check the restored files and symlinks:

```bash
test -s /var/lib/radarr/config.xml
test -s /var/lib/sonarr/config.xml
test -s /var/lib/prowlarr/config.xml
test -s /var/lib/seerr/settings.json
test -s /var/lib/decypharr/db/entries.db
test -d /var/lib/decypharr/usenet/meta
find /data/media -type l -print -quit
systemctl status jellyfin radarr sonarr prowlarr seerr decypharr
```

Open Jellyfin and the \*arr/Seerr interfaces through the ingress and confirm the
library, indexers, and request queue are present. Then take a fresh backup and
confirm it succeeded:

```bash
systemctl start media-backup.service
systemctl show -p Result --value media-backup.service
journalctl -u media-backup.service -n 50 --no-pager
```

Do not run the fresh backup until the restored state is verified; otherwise it
replaces the recovery point with a bad snapshot.

## Failure modes and rollback

- **B2 `Class B` cap or transaction error:** raise the cap or wait for the
  billing period to reset, then rerun. The restore has not completed; inspect
  the unit before retrying.
- **SOPS activation fails:** the host key is missing or does not match the
  encrypted recipients. Recover the original key or rekey as above. Do not log
  the secret values or the private identity.
- **Latest snapshot is bad:** use the manual path with an earlier snapshot ID.
  Retention keeps 7 daily, 4 weekly, and 6 monthly snapshots by default. Check
  Jellyfin integrity and the PostgreSQL tables before taking a new backup.
- **Jellyfin database integrity fails:** choose an earlier snapshot; do not
  overwrite the healthy database with a bad one.
- **PostgreSQL restore errors:** check database roles, ownership, and the
  `--role` values. The module creates the four databases and roles on first
  deployment; a bare PostgreSQL instance may not.
- **Symlinks resolve to missing media:** expected when the provider has expired
  the release. The backup restores the library metadata, not the bytes.
- **The wrong host's snapshot is restored:** the default host label is
  `media-stack`. Confirm the `--host` value and never point two active hosts at
  the same repository path with the same label.
- **A restore overwrote newer state:** stop, do not take a new backup, and
  restore the appropriate earlier snapshot with the manual path. The automatic
  service always uses `latest`.

## After recovery

- Remove temporary credential files and any recovered key copies from
  `$HOME/media-recovery` and `/tmp`.
- Rotate the B2 application key if it was exposed; update
  `secrets/media-backup/secrets.yaml` and the B2 account.
- Re-enable the backup timer after verification if it was disabled.
- Confirm one clean backup exists after the restored state is verified.
- Record the recovery date and the snapshot used in the incident notes.
- If you rekeyed the SOPS group, remove the old recipient only after the new
  host has successfully decrypted the secrets and completed a restore.
