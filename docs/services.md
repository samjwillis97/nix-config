# Stateful services and access boundaries

This guide covers the service paths where a rebuild is not the same thing as a
restore: the Supernote private cloud, the local ingress and Cloudflare Tunnel
boundary, the stateful Actual and media modules, Tailscale, and the container
entry points used by hosts. It is deliberately selective rather than a list of
every enabled service or listener.

The source of truth is always the effective host configuration. Reusable modules
live in [`nixos-modules/`](../nixos-modules/), and host-specific choices live in
[`nixos-hosts/`](../nixos-hosts/). A host's `default.nix` can override module
defaults, so do not copy a hostname, route, port, image tag, or container name
from an old deployment into a maintenance command.

## Find the effective configuration first

Set the flake configuration key explicitly, then inspect only the options needed
for the operation. These commands print configuration, not decrypted secret
contents:

```sh
host_name="${NIXOS_HOST:?set NIXOS_HOST to a nixosConfigurations key}"

nix eval --json ".#nixosConfigurations.${host_name}.config.my.supernote"
nix eval --json ".#nixosConfigurations.${host_name}.config.my.ingress"
nix eval --json ".#nixosConfigurations.${host_name}.config.my.cloudflared"
nix eval --json ".#nixosConfigurations.${host_name}.config.virtualisation.oci-containers.backend"
nix eval --json ".#nixosConfigurations.${host_name}.config.virtualisation.oci-containers.containers"
```

Use the evaluated `dataDir`, `databaseInitScript`, `databaseUser`,
`networkName`, `httpPort`, HTTPS settings, and secret _names_ when planning a
Supernote operation. The container and systemd names come from the effective
OCI container declarations and generated units. Confirm the runtime and names
on the machine before using `systemctl` or the container CLI:

```sh
systemctl list-unit-files --type=service
```

Never print or put secret values in a Nix expression, shell history, or a
maintenance transcript. The [secrets guide](../secrets/README.md) explains
SOPS identities, runtime secret paths, rekeying, and machine bootstrap.

## Supernote private cloud

The implementation is [`nixos-modules/supernote/default.nix`](../nixos-modules/supernote/default.nix).
Enabling `my.supernote` also enables the repository's container support and
defines a private container network, MariaDB, Redis, a note-conversion
container, and the application container. The application depends on the
other three containers. Persistent bind mounts are all below `my.supernote.dataDir`;
the module creates separate areas for MariaDB, Redis, application data, and
Supernote working data (`sndata`, including recycle, conversion, log, and
certificate directories).

The host configuration must import a Supernote secret module and map
`my.supernote.secrets.mysqlRootPassword`, `mysqlPassword`, and `redisPassword`
to names declared in `config.sops.secrets`. The module asserts that all three
names exist. At activation, sops-nix renders the values into a protected
runtime environment file and changes to that template restart the Supernote
containers. This is why the values belong in SOPS rather than in Nix source or
an image environment committed to the store.

### Bootstrap is not migration

For a first deployment, `databaseInitScript` defaults to the bundled
[`supernotedb.sql`](../nixos-modules/supernote/supernotedb.sql). The host file is
mounted read-only at the fixed path
`/docker-entrypoint-initdb.d/supernotedb.sql` inside the MariaDB container. The
MariaDB image consumes that directory only while initializing an empty bound
data directory. Rebuilding the NixOS system, recreating a container, or
restarting the application does **not** cause the script to be replayed against
an already initialized database.

The checked-in SQL is a bootstrap/schema snapshot. It creates tables and seed
rows, but it also contains cleanup and schema-changing statements, including
`TRUNCATE`, `DELETE`, and `ALTER TABLE`. It is therefore not a general-purpose
migration runner and is not a backup. In particular:

- Do not remove or rename the MariaDB data directory just to force initialization.
- Do not import the bootstrap file into a live database without a verified,
  restorable backup, a maintenance window, and a deliberate review of the SQL.
- Do not assume that an application image upgrade automatically migrates the
  database. No repository-owned Supernote migration or restore automation is
  declared here; follow the application/vendor procedure for an upgrade and
  record the result.
- Treat the database, Redis state, application data, and note files as one
  recovery set unless the vendor documents a safe way to rebuild one component.

When an existing deployment is missing a schema or a deliberate repair requires
reapplying the checked-in SQL, first stop writes and make an independent backup.
Use values from the effective configuration rather than assuming the example's
runtime, names, or database name:

```sh
container_runtime="${CONTAINER_RUNTIME:?set to the configured OCI runtime}"
database_container="${SUPERNOTE_DATABASE_CONTAINER:?set to the effective MariaDB container name}"
database_name="${SUPERNOTE_DATABASE_NAME:?set to the effective database name}"
database_init_path="${SUPERNOTE_DATABASE_INIT_PATH:-/docker-entrypoint-initdb.d/supernotedb.sql}"
service_unit="${SUPERNOTE_SERVICE_UNIT:?set to the generated Supernote application service unit}"

sudo systemctl stop "$service_unit"
sudo "$container_runtime" exec "$database_container" sh -c \
  'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" "$1" < "$2"' \
  sh "$database_name" "$database_init_path"
sudo systemctl start "$service_unit"
```

The password expansion in the command occurs inside the database container,
where the module's secret environment is available; it is not read from the
host shell. The path supplied as `database_init_path` is the path _inside_ the
container. If a custom `databaseInitScript` is configured, the module still
mounts it at that in-container path. Verify service logs and application
behavior after the operation; a successful SQL command alone does not prove
that existing application data is consistent.

This preserves the existing module contract, but `-p"$MYSQL_ROOT_PASSWORD"`
expands the password in the MariaDB client process arguments inside the
container while the command runs. Perform the repair only on a trusted host;
if an approved MariaDB client credential-file mechanism is available, prefer it
over exposing a password in process listings. Never put the actual password in
the host command line or shell history.

### Data and backup boundaries

`my.supernote.dataDir` is the storage boundary to preserve across a rebuild or
host replacement. The module bind-mounts the application state below that
option and creates the working directories below; the certificate directory can
be overridden, and direct certificate/key files can be mounted instead:

The important paths (shown as text, not commands) are:

- `${data_dir}/mariadb`
- `${data_dir}/redis`
- `${data_dir}/supernote_data`
- `${data_dir}/sndata/recycle`
- `${data_dir}/sndata/convert`
- `${data_dir}/sndata/logs/app`
- `${data_dir}/sndata/logs/cloud`
- `${data_dir}/sndata/logs/web`
- `${data_dir}/sndata/cert` (the default `certificateDirectory`)

Backing up the whole data directory is less error-prone than selecting one
subdirectory. A filesystem copy of a live MariaDB directory is not automatically
a consistent database backup; use a MariaDB-consistent dump or snapshot
procedure, and coordinate it with application writes. Preserve the Redis data
and application/note bind mounts as well unless a tested vendor recovery plan
says they can be rebuilt. Preserve certificates and keys separately when they
are supplied through SOPS or another path rather than the data directory.

The repository does not schedule, upload, verify, or restore these backups.
Before deleting a data directory, changing database images, changing the
Supernote schema, or replacing a machine, confirm that a backup can be read and
that the required SOPS identities and secret files are also recoverable. A
copy of `supernotedb.sql` can recreate the baseline schema; it cannot recreate
users, note metadata, files, Redis state, credentials, or other live data.

If custom Supernote HTTPS is enabled, `https.domain` requires a certificate and
key. The module accepts either a certificate/key pair supplied as SOPS-decrypted
files or a certificate directory containing the configured certificate and key
names; setting only one of the pair is rejected. The local ingress route uses
the configured HTTP origin, so enabling the container's separate HTTPS mapping
does not by itself create a public route.

## Ingress and Cloudflare Tunnel boundaries

The local ingress module is [`nixos-modules/ingress.nix`](../nixos-modules/ingress.nix).
When at least one `my.ingress.routes` entry exists, Nginx listens on the loopback
addresses and the configured `my.ingress.listenPort`. Every route must define
exactly one of `upstream` or `root`:

- An `upstream` route proxies to a local HTTP origin. Its `websockets` flag
  controls the standard WebSocket upgrade handling.
- A `root` route serves static files.
- A route's default subdomain is derived from its route name and the host name;
  set `subdomain` explicitly when that is not appropriate.

`my.ingress.listenPort` controls the Nginx side only. The current Terranix
Cloudflare renderer uses its own fixed loopback origin and the flake does not
pass `listenPort` through to it, so changing the NixOS listener alone can
disconnect the Tunnel. Treat a non-default listener as a paired NixOS/Terranix
change and inspect both generated configurations before applying it.

The Supernote module adds an upstream route to its configured HTTP origin and
adds the vendor-specific Nginx settings: a large request-body limit, buffering,
long timeouts, forwarded headers, and a dedicated `/socket.io/` upgrade
location. Automatic synchronization may expose another fixed container mapping,
but the module does not add that mapping as a second Cloudflare route. Keep the
route behavior in the module source rather than copying listener values into
runbooks.

Actual and Jellyfin routes opt into WebSocket proxying in their respective
modules. Jellyfin's `openFirewall` option is independent of its ingress option:
opening a firewall listener is not the same as adding a local Nginx route or a
Cloudflare DNS/Tunnel route.

[`nixos-modules/cloudflared.nix`](../nixos-modules/cloudflared.nix) runs the
Tunnel connector as a systemd service. Its token is loaded as a credential from
the configured SOPS path, and the connector starts after network-online and
Nginx. Enabling `my.cloudflared.connector` without `my.cloudflared.enable` is a
configuration error. A tunnel token grants access to the remotely managed
Tunnel; keep it secret and rotate it through the secrets workflow.

The flake derives the Cloudflare host map from NixOS configurations that enable
Cloudflared and their local ingress routes. The
[`Terranix Cloudflare module`](../terranix/cloudflare.nix) renders the public
hostname and DNS/Tunnel resources, then sends Tunnel traffic to the host's
loopback Nginx listener with the route's internal host header. The resulting
boundary is:

```text
Cloudflare edge/DNS -> Cloudflare Tunnel connector -> loopback Nginx -> local upstream
```

The Tunnel does not publish every container mapping, bypass Nginx, or make a
service reachable on the LAN or Tailscale interface. A route can be valid in
NixOS while its public DNS/Tunnel resources are absent or stale until the
Terranix/OpenTofu configuration is applied. Conversely, applying Cloudflare
resources does not create a local service. Use the
[`Terranix operations guide`](../terranix/README.md) for the generated
configuration shell, credential handling, and `tofu plan`/`tofu apply` workflow;
do not put Cloudflare credentials in Nix source.

## Actual and media state

The Actual wrapper is [`nixos-modules/actual.nix`](../nixos-modules/actual.nix).
`my.actual.enable` enables the NixOS `services.actual` service and selects its
package from the `unstable` input; it binds the service to loopback.
`my.actual.ingress.enable` only adds a local Nginx upstream with WebSocket
support. The wrapper does not define a backup, migration, export, or restore
job. Discover the effective `services.actual` state path and any service-specific
database behavior from the evaluated configuration and the upstream NixOS
module before taking a backup or changing the package.

The media wrapper is [`nixos-modules/media/default.nix`](../nixos-modules/media/default.nix),
with Jellyfin settings in [`media/jellyfin.nix`](../nixos-modules/media/jellyfin.nix).
Enabling the media module enables the external `nixflix` stack and its Postgres
component; it does not add a repository backup job. Jellyfin API/admin
credentials, optional user password files, and Xtream provider credentials are
passed as secret files. A user entry follows the host's configured
`jellyfin/users/<user>/password` naming convention; the literal user name is a
host choice, not a documentation constant.

Back up the effective media state, the Postgres data, and any media paths that
are not reproducible from another source. The wrapper leaves the exact
`nixflix` media/state locations to that dependency and host configuration, so
inspect those values rather than assuming a path. Test a restore with the
service stopped or in an isolated host; this repository does not implement
media, Postgres, or Jellyfin backup/restore automation.

## Tailscale trust and exit-node limits

The Tailscale module is [`nixos-modules/tailscale.nix`](../nixos-modules/tailscale.nix).
It loads the auth key from the configured secret path, enables `tailscaled`,
trusts the `tailscale0` interface in the host firewall, allows the Tailscale
UDP listener, and uses loose reverse-path checking. This is host firewall
plumbing, not a blanket publication rule:

- Services that bind only to loopback (including the shared Nginx ingress and
  the Actual origin) are not automatically reachable at the host's Tailscale
  address.
- `openFirewall` or a Tailscale interface trust does not replace an explicit
  service listener, an ingress route, or Tailscale ACL policy.
- The auth key is a bootstrap credential. Keep it in SOPS, use the narrowest
  scope and lifetime supported by the Tailscale control plane, and do not put it
  in the flake or a shell command line.

`my.tailscale.exitNode.enable` currently adds IPv6 forwarding sysctl state only.
It does not advertise an exit node, configure IPv4 forwarding/NAT, approve a
route in the control plane, or change ACLs. Completing those control-plane and
networking steps is an operator responsibility; do not describe this option as
an already-working exit-node deployment.

## Container and VM entry points

The generic container module is [`nixos-modules/virtualisation/default.nix`](../nixos-modules/virtualisation/default.nix).
`my.virtualisation.containers.backend` accepts `podman` or `docker`; the default
is a module value, not a reason to hard-code a runtime in an operations script.
The module sets the matching NixOS OCI backend and, for Podman, enables Docker
compatibility and DNS on the default network. Supernote enables container
support itself; hosts that run other OCI services must enable it explicitly.

Use the effective backend when inspecting or restarting a container. Generated
OCI declarations become systemd units, so prefer those units for lifecycle
operations and use the matching runtime only for deliberate maintenance. Do
not delete anonymous volumes or bind-mounted data as a substitute for a
restore.

For a host that imports the NixOS `qemu-vm` module, build the generated VM
launcher without naming a particular machine in the command:

```sh
host_name="${NIXOS_HOST:?set NIXOS_HOST to a qemu-vm nixosConfigurations key}"
nix build --no-link ".#nixosConfigurations.${host_name}.config.system.build.vm"
```

The resulting launcher is useful for testing a new service configuration or a
restore copy without touching the persistent host. A VM disk is not a backup:
its machine identity, SOPS system key, and service data disappear with the disk
unless they are stored and backed up separately. See the
[secrets guide](../secrets/README.md) before cloning or replacing a secret-enabled
VM.

## Source map

- [Supernote module](../nixos-modules/supernote/default.nix) and [bundled SQL](../nixos-modules/supernote/supernotedb.sql)
- [Local ingress](../nixos-modules/ingress.nix) and [Cloudflared connector](../nixos-modules/cloudflared.nix)
- [Actual wrapper](../nixos-modules/actual.nix)
- [Media wrapper](../nixos-modules/media/default.nix) and [Jellyfin wrapper](../nixos-modules/media/jellyfin.nix)
- [Tailscale](../nixos-modules/tailscale.nix) and [container backend](../nixos-modules/virtualisation/default.nix)
- [Host-specific service settings](../nixos-hosts/)
- [SOPS runtime and recovery procedures](../secrets/README.md)
- [Terranix/OpenTofu operations](../terranix/README.md)
