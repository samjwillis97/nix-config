# Terranix and Cloudflare infrastructure

This directory contains the Terranix module that renders the repository's
Cloudflare infrastructure as Terraform JSON for OpenTofu. It does not deploy
NixOS hosts, create SOPS files, or provision the Cloudflare API token.

The flake registers the Terranix configuration
`terranix.terranixConfigurations.cloudflare` in [`flake.nix`](../flake.nix).
The configuration imports [`cloudflare.nix`](cloudflare.nix), passes the
Cloudflare account and zone settings through `extraArgs`, and uses a dedicated
working directory. The account and zone identifiers are configuration values,
not secrets; their values intentionally are not repeated here.

## Discover the generated interface

The Terranix flake module exports a package and development shell for each
Terranix configuration. Discover the names for the current system instead of
assuming that a host or package inventory is unchanged:

```console
nix flake show

system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
nix eval --json ".#packages.${system}" --apply builtins.attrNames
nix eval --json ".#devShells.${system}" --apply builtins.attrNames
```

For this repository, the Terranix name shown by those commands is
`cloudflare`. It is exposed as:

- `packages.<system>.cloudflare`: the default **apply** script, with
  `init`, `plan`, `apply`, and `destroy` scripts available as package
  passthru attributes.
- `devShells.<system>.cloudflare`: a shell containing those scripts and the
  wrapped OpenTofu executable.

There is no `apps.<system>.cloudflare` output. The regular `apps` output is
separate; the package passthru is why the following `nix run` forms work:

```console
nix run .#cloudflare              # init, then apply
nix run .#cloudflare.init         # init
nix run .#cloudflare.plan         # init, then plan
nix run .#cloudflare.apply        # init, then apply
nix run .#cloudflare.destroy      # init, then destroy; destructive
```

The generated scripts have fixed commands. They are useful for the normal
workflow, but they do not turn an arbitrary OpenTofu argument into a reviewed
plan. For direct OpenTofu invocations, enter the matching shell:

```console
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
nix develop .#cloudflare
init
plan
apply
```

The export is only an example of making the workstation age identity
discoverable. Follow the [Secrets guide](../secrets/README.md) for creating or
recovering an identity. Do not print the identity or decrypted credentials.

Re-enter the generated shell after changing the Terranix configuration. The
upstream Terranix flake module documents that the invocation scripts in an
already-created shell continue to target the older generated configuration.

To inspect which NixOS hosts and ingress route names currently feed this
configuration, evaluate the non-secret `cloudflareHosts` output:

```console
nix eval --json .#cloudflareHosts \
  --apply 'builtins.mapAttrs (_: host: builtins.attrNames host.routes)'
```

`cloudflareHosts` is an output of [`flake-module.nix`](../flake-module.nix),
not a manually maintained list. It filters the generated NixOS configurations
to those with `my.cloudflared.enable = true`. For every selected host it maps
the configured `my.ingress.routes` and adds the route attribute name as
`internalHost`.

## Working directory and state

The flake sets this configuration's workdir to
`.terranix/cloudflare`. The Terranix wrapper and scripts implement the
following sequence:

1. Create the workdir if it does not exist.
2. Change into that workdir.
3. Run the SOPS credential prefix.
4. Invoke OpenTofu.

Each generated script also symlinks the immutable Terranix JSON result to
`.terranix/cloudflare/config.tf.json` before invoking the wrapper. The
directory is ignored by Git, but it is not automatically encrypted, backed up,
or remote. The module has no Terraform backend block, so OpenTofu uses its
default local state in this directory. Treat state, provider lock data, plan
files, and logs as infrastructure-sensitive material; a `sensitive` output
still may be present in state.

The workdir is a local operator boundary, not a collaboration or recovery
mechanism. Do not commit it, upload it to an issue, or place it in an
unprotected backup. If it is lost, recovery may require importing existing
Cloudflare objects and reconciling them with a new state file. Concurrent
operators also do not get remote state locking from this configuration.

## Credentials and bootstrap order

The OpenTofu wrapper is defined in [`flake.nix`](../flake.nix). It adds SOPS
as a runtime input and, immediately before every OpenTofu invocation, runs the
equivalent of:

```sh
CLOUDFLARE_API_TOKEN="$(
  sops \
    --decrypt \
    --extract '["api-token"]' \
    secrets/terranix/cloudflare.yaml
)"
export CLOUDFLARE_API_TOKEN
```

The actual wrapper uses the flake-relative path to the encrypted file. The
token is therefore decrypted at command runtime and passed to the child
OpenTofu process through `CLOUDFLARE_API_TOKEN`; it is not read during Nix
evaluation or embedded as plaintext in a Nix derivation. The encrypted file
and its recipient policy are maintained separately from this module:

- [`secrets/terranix/cloudflare.yaml`](../secrets/terranix/cloudflare.yaml)
  holds the encrypted `api-token` value.
- [`.sops.yaml`](../.sops.yaml) controls which workstation identities can
  decrypt that file.
- [`secrets/README.md`](../secrets/README.md) documents age identity setup and
  rekeying.

Before the first plan, an operator must have both a usable Cloudflare API token
and a SOPS identity authorized for this file. The repository does not create
the token, declare its Cloudflare permissions, or rotate it. Choose
least-privilege permissions according to the resources in
[`cloudflare.nix`](cloudflare.nix) and the account's policy; do not put a
token in Nix source, shell history, command arguments, or a checked-in file.

The bootstrap dependency is intentionally one-way:

1. The API token allows OpenTofu to create or update the tunnel resources and
   DNS records.
2. The apply obtains the sensitive `cloudflare_tunnel_tokens` output.
3. An operator encrypts each connector token into the appropriate host secret.
4. A NixOS deployment activates the connector service.

The OpenTofu wrapper does not write a token into SOPS automatically, and a
NixOS activation does not create a Cloudflare tunnel. Keep those operations
separate.

## What the Cloudflare module generates

`cloudflare.nix` receives `cloudflareHosts` and
`cloudflareSettings` through Terranix `extraArgs`. The settings are defined in
the `cloudflare` entry in [`flake.nix`](../flake.nix):

- `accountId` is used by each Cloudflare tunnel and tunnel-token data source.
- `zoneId` is used by each generated DNS record.
- `zoneName` is appended to every route subdomain to form its public hostname.

The module creates the following OpenTofu objects for every selected NixOS
host:

- One `cloudflare_zero_trust_tunnel_cloudflared.host` tunnel, named from the
  host attribute and configured with `config_src = "cloudflare"`.
- One `cloudflare_zero_trust_tunnel_cloudflared_config.host` configuration
  containing the tunnel ingress rules.
- One `cloudflare_dns_record.route` record for each host/route pair.
- One `data.cloudflare_zero_trust_tunnel_cloudflared_token.host` data source
  and the sensitive `cloudflare_tunnel_tokens` output map.

The tunnel's ingress configuration is managed by the generated Cloudflare
configuration resource (`config_src = "cloudflare"`); the NixOS connector
receives a token, not a checked-in local tunnel configuration.

For every ingress route, the module:

1. Derives `hostname` from the route's `subdomain` and `zoneName`.
2. Sends the tunnel request to the loopback nginx listener configured by
   [`nixos-modules/ingress.nix`](../nixos-modules/ingress.nix).
3. Sets `origin_request.http_host_header` to the route name stored as
   `internalHost`.
4. Adds a final `http_status:404` ingress rule.
5. Creates a proxied CNAME to the selected tunnel's
   `cfargotunnel.com` address.

The NixOS ingress module exposes `my.ingress.listenPort` for nginx's loopback
listener and creates a virtual host for each route. The Terranix module does
not consume that option: its generated origin URL uses a fixed loopback port,
and `cloudflareHosts` exports route metadata without a port. Changing
`my.ingress.listenPort` alone therefore leaves nginx and the tunnel origin out
of sync; keep the two source definitions aligned deliberately.

A route must define exactly one of
`upstream` or `root`; `websockets` controls proxy upgrades for upstream
routes. The Cloudflare route's public subdomain and the nginx virtual-host
name are separate concepts: the former is externally visible, while the
route-name host header selects the local origin.
Unless a route sets `subdomain` explicitly, the ingress option defaults it to
`${route-name}-${networking.hostName}`. Renaming the NixOS host or route can
therefore change the public hostname and the corresponding DNS resource.

The `moved` entries in `cloudflare.nix` cover the specific migration from an
older host-keyed DNS record address to the current route-keyed address when a
route's subdomain equals its tunnel host. This preserves state for that known
migration; it is not a general rollback or rename facility.

## Onboard a host or route

The reusable NixOS modules are discovered automatically by
[`flake-module.nix`](../flake-module.nix). A host is eligible for this
infrastructure only when its NixOS configuration enables
`my.cloudflared.enable`. A connector is optional at the Terranix layer: a
tunnel and DNS can be generated before a connector is deployed, but traffic
will not reach an origin until a connector is running.

An onboarding host normally needs all of the following:

```nix
{ config, secretModules, ... }:
{
  imports = [ secretModules.cloudflared ];

  my = {
    cloudflared = {
      enable = true;
      connector = {
        enable = true;
        tokenFile = config.sops.secrets."cloudflared-token".path;
      };
    };

    # Enable an existing service's ingress option, or define a route in a
    # host/module appropriate for the service.
  };
}
```

The `cloudflared` secret module derives the encrypted filename from
`config.networking.hostName`: it reads
`secrets/cloudflared/<host-name>.yaml` and declares the
`cloudflared-token` secret. Create that encrypted file and its SOPS creation
rule before deploying the connector; neither Terranix nor the NixOS module
creates it.

For a low-risk route smoke test, the repository also contains the optional
`my.hello` module. Enabling both `my.hello.enable` and
`my.hello.ingress.enable` adds a static route; it is not enabled by the
Cloudflare module itself. A production route can instead come from an
existing service module such as the media, Actual, or Supernote modules. The
route is included only when it belongs to a host that also has
`my.cloudflared.enable`.

Use this order when onboarding:

1. Add or enable the NixOS host and route, and import
   `secretModules.cloudflared` if that host will run a connector.
2. Evaluate `.#cloudflareHosts` and check that the expected host and route
   names appear without printing any secret.
3. Run a Terranix plan, review tunnel, ingress, and DNS changes, then apply
   the infrastructure.
4. Retrieve the resulting tunnel token through the wrapper and place it in
   the host-specific encrypted SOPS file.
5. Build and deploy the NixOS configuration using the repository's normal
   deployment procedure, then verify the connector service and origin without
   displaying the token.

## Provisioning connector tokens safely

The output is a map keyed by selected host name. It is marked sensitive, but
requesting it in JSON or raw form intentionally reveals a credential to the
operator. Retrieve only the one host needed and keep the temporary file
private. The generated cloudflare shell does not add `jq`; provide it
separately (for example with `nix shell nixpkgs#jq`) before running this
pipeline:

```console
nix develop .#cloudflare
init

host_name='HOST_NAME_FROM_CLOUDFLARE_HOSTS'
umask 077
token_file="$(mktemp)"
trap 'rm -f "$token_file"' EXIT
set -o pipefail
tofu output -json cloudflare_tunnel_tokens |
  jq -er --arg host "$host_name" '.[$host]' > "$token_file"

sops edit "secrets/cloudflared/${host_name}.yaml"
```

In the SOPS editor, set the `cloudflared-token` YAML key from the protected
temporary file, save, and close. Do not use `cat`, `echo`, debug tracing, or
logs that expose the token. The trap removes the temporary file when the shell
exits; remove it explicitly before sharing or closing the terminal if the
workflow ends early. If the host's SOPS creation rule or encrypted file does
not exist, establish that access boundary first using the
[Secrets guide](../secrets/README.md).

On the NixOS side, [`nixos-modules/cloudflared.nix`](../nixos-modules/cloudflared.nix)
requires connector enablement to imply `my.cloudflared.enable`. Its systemd
unit:

- waits for the network and nginx;
- runs with `DynamicUser`;
- uses systemd `LoadCredential` to stage the SOPS-created token;
- invokes `cloudflared tunnel --no-autoupdate run --token-file %d/token`;
- restarts after failure.

The host's SOPS system identity decrypts the token; the short-lived service
credential is separate from the workstation identity that decrypts the
Cloudflare API token. The connector does not need the Cloudflare API token,
and the Terraform wrapper does not need the tunnel token.

## Safe plan, apply, and rollback boundaries

The normal generated scripts always run `tofu init` first. For an apply that
must use the exact reviewed plan, use the wrapper directly after `init`:

```console
nix develop .#cloudflare
init
tofu plan -out=reviewed.tfplan
tofu show reviewed.tfplan
tofu apply reviewed.tfplan
```

The wrapper changes into `.terranix/cloudflare` before each command, so the
relative `reviewed.tfplan` file is created and consumed in the ignored
workdir. The plan file can contain infrastructure-sensitive values. Keep it
there, do not upload it, and remove it after the apply when it is no longer
needed. The one-command `apply` script performs a fresh plan/apply instead of
consuming `reviewed.tfplan`.

`destroy` is exposed because the upstream Terranix interface exposes it; it
is not a routine rollback and can remove DNS records and tunnels. Require an
explicit operator decision and a current plan before using it. There is no
repository-provided automatic rollback, remote state backend, or
transaction spanning Cloudflare and NixOS deployment. If a source change
needs to be undone, revert the Nix/Terranix source in version control, run a
new plan, and apply only after checking the resulting resource actions. A
partially failed apply may have changed Cloudflare before failing; inspect the
local state and plan again rather than assuming an all-or-nothing operation.

Reverting Cloudflare source also does not revert a NixOS deployment, and
reverting a NixOS deployment does not remove Cloudflare resources. Restore
those planes independently. Preserve a secure copy of local state before
recovery work; losing it can require imports and manual reconciliation.

## Source map

- [`flake.nix`](../flake.nix): Terranix registration, workdir, OpenTofu
  wrapper, SOPS extraction, account/zone settings, and the imported
  Terranix flake-module output contract.
- [`flake-module.nix`](../flake-module.nix): NixOS configuration discovery
  and the `cloudflareHosts` export.
- [`cloudflare.nix`](cloudflare.nix): generated tunnels, ingress, DNS,
  migration addresses, data sources, and outputs.
- [`nixos-modules/ingress.nix`](../nixos-modules/ingress.nix): route schema,
  nginx loopback listener, and upstream/root assertion.
- [`nixos-modules/cloudflared.nix`](../nixos-modules/cloudflared.nix):
  connector service and systemd credential boundary.
- [`secrets/cloudflared/default.nix`](../secrets/cloudflared/default.nix):
  host-derived tunnel-token secret files.
- [`docs/operations.md`](../docs/operations.md): repository-wide deployment
  and closure guidance.
