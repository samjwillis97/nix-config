# Build, deploy and inspect configurations

[Project overview](../README.md) · [Development and CI](development.md) ·
[Secrets](../secrets/README.md) · [Services](services.md)

Commands below run from the repository root in a shell with Nix available.
Replace uppercase placeholder values with names returned by the discovery
commands. Evaluation is not a build; a build is not activation; activation is not
a service-data migration or backup.

## Select an output

```sh
nix eval --json .#nixosConfigurations --apply builtins.attrNames
nix eval --json .#darwinConfigurations --apply builtins.attrNames
```

Choose **one** target definition appropriate to the platform:

```sh
# NixOS
host='HOST_OUTPUT'
target="nixosConfigurations.\"${host}\".config.system.build.toplevel"
```

```sh
# Darwin
host='HOST_OUTPUT'
target="darwinConfigurations.\"${host}\".system"
```

Both select a derivation, not the whole configuration object. Whole system
values contain functions and cannot be encoded as JSON. A derivation path is a
useful evaluation-only check:

```sh
nix eval --raw ".#${target}.drvPath"
nix build --dry-run ".#${target}"
```

`--dry-run` evaluates and reports what would be built or fetched; it does not
produce the target. Evaluation may still fetch inputs. Build on a compatible
system or use an appropriately configured remote builder: a Darwin machine does
not natively build Linux system closures just because they evaluate.

For a standalone package, select its system and name using the
[package guide](../packages/README.md), then set
`target="packages.${system}.\"${package}\""` for the same inspection/build tools.

## Build before activating

```sh
nix build -L --out-link ./result ".#${target}"
nix path-info -Sh ./result
```

The result symlink is a build output, not a switched generation. For CI or
one-off builds where no result link is wanted, use `nix build --no-link -L` with
the same installable. A result/profile link helps keep its closure reachable by
garbage collection while you inspect it.

### Local NixOS activation

On the intended NixOS machine, after building and reviewing the closure:

```sh
sudo nixos-rebuild test --flake ".#${host}"
# After checking services and connectivity:
sudo nixos-rebuild switch --flake ".#${host}"
```

`test` activates without making the result the default boot configuration;
`switch` activates and updates that default. Both can disrupt running services.
A new machine needs an installation/bootstrap procedure first; a flake host
entry does not install NixOS or partition disks. See [adding hosts](../nixos-hosts/README.md).

### Local Darwin activation

On the intended macOS machine with nix-darwin already installed:

```sh
sudo darwin-rebuild switch --flake ".#${host}"
```

Initial nix-darwin installation is a separate prerequisite. Use the lock-aligned
upstream installer guidance linked in the [Darwin host guide](../darwin-hosts/README.md),
not an assumed rebuild command on a machine where it does not yet exist.
Embedded Home Manager configurations activate with their host; do not assume a
standalone `home-manager switch --flake` output is provided.

## Inspect packages and closure size

A directly configured package list is **not** the full closure. Services,
activation scripts, propagated dependencies, Home Manager and the toolchain may
add store references beyond `environment.systemPackages`.

For either host platform, set `configuration` appropriately:

```sh
configuration="nixosConfigurations.\"${host}\""
# On Darwin instead:
# configuration="darwinConfigurations.\"${host}\""

nix eval --json ".#${configuration}.config.environment.systemPackages" \
  --apply 'packages: map (package: package.name) packages'
nix eval --json ".#${configuration}.config.system.stateVersion"
```

To discover embedded homes, enable Home Manager on the host and inspect:

```sh
nix eval --json ".#${configuration}.config.home-manager.users" \
  --apply builtins.attrNames
user='USER_FROM_THAT_OUTPUT'
nix eval --json ".#${configuration}.config.home-manager.users.\"${user}\".home.packages" \
  --apply 'packages: map (package: package.name) packages'
```

For a built result:

```sh
# Total transitive closure size, human readable.
nix path-info -Sh ./result

# Every referenced store path and its individual size.
nix path-info -rsSh ./result

# Explain why a particular store dependency is reachable.
dependency='STORE_PATH_FROM_CLOSURE_OUTPUT'
nix why-depends ./result "$dependency"
```

`-S` includes transitive closure sizes; `-s` is the path's own size. Do not sum
per-path closure sizes: shared dependencies would be counted repeatedly. To
inspect paths that are not yet present, build/fetch them first rather than
assuming `nix path-info` realizes an unbuilt configuration for you.

## Compare closures

Closure diffs answer which store paths/packages and sizes changed. They do not
show every option change, prove a service is healthy, or explain compatibility
of data written by different versions.

### Before and after a working-tree change

Choose `target` as above. **Before editing/updating inputs**, create the baseline:

```sh
comparison=$(mktemp -d)
printf 'Comparison directory: %s\n' "$comparison"
nix build -L --profile "$comparison/before" ".#${target}"
```

Keep that shell and directory. Make the change, ensure new source files are
visible to the Git-backed flake, then build the candidate into a separate profile:

```sh
nix build -L --profile "$comparison/after" ".#${target}"
nix store diff-closures "$comparison/before" "$comparison/after"
```

For Dix's presentation, use the tool supplied by `nix develop`:

```sh
dix --help
dix --force-correctness --color never \
  "$comparison/before" "$comparison/after"
```

Do not build both profiles from the edited tree and call one a baseline. Keep
both profiles until review is complete; remove only the temporary comparison
directory you created when no longer needed. Removing a comparison profile is
not rolling back the running system.

### Compare a committed revision with the working tree

If there was no pre-change snapshot, obtain a baseline from a selected local Git
revision. This uses that revision's own flake and lock file:

```sh
base_ref='BASE_GIT_REF'
base_rev=$(git rev-parse --verify "${base_ref}^{commit}")
repo=$(git rev-parse --show-toplevel)
comparison=$(mktemp -d)

nix build -L --profile "$comparison/before" \
  "git+file://${repo}?rev=${base_rev}#${target}"
nix build -L --profile "$comparison/after" ".#${target}"
nix store diff-closures "$comparison/before" "$comparison/after"
```

The selected output must exist at both revisions. A newly added output has no
old closure; an output rename may require different old/new attributes. The
working-tree candidate includes modifications to tracked files, not ordinary
untracked files. Large or cross-platform baselines can require substantial
builds and suitable builders.

### Compare the running system with a candidate

On a configured NixOS or Darwin host where `/run/current-system` points to its
active system, build the matching host's candidate and compare:

```sh
nix build -L --out-link ./result ".#${target}"
nix store diff-closures /run/current-system ./result
```

This is the **running system versus the candidate**, not necessarily the base
Git revision versus HEAD. Do not use another host's current system as a baseline
for a meaningful host upgrade review. CI's `my.dix.enable` workflow instead
builds PR base/head profiles; see [CI](development.md#continuous-integration).

## Remote deployment

The NixOS `my.deploy-rs` module establishes SSH deployment access.
`my.deploy-rs.enable` requires a nonempty `my.deploy-rs.authorizedKeys` list and
exports a node. `my.deploy-rs.githubActions.enable` additionally selects it for
CI. Discover actual targets and connection identities rather than assuming
an inventory or username:

```sh
nix eval --json .#deploy.nodes --apply builtins.attrNames
host='DEPLOY_NODE_FROM_OUTPUT'
nix eval --json ".#deploy.nodes.\"${host}\""
```

The deployment account has passwordless sudo and trusted Nix-daemon access:
its SSH key is **root-equivalent access**, not a limited upload credential.
Protect it accordingly. The generated node uses the output name as its SSH
hostname; DNS/private-network resolution must work from the deployment client.
Inspect effective `sshUser` and activation `user` in the node instead of copying
those names into independent scripts.

Bootstrap checklist:

1. Install the host and apply its initial account, SSH and networking settings
   through a channel you already trust. Deploy-rs cannot create its own initial
   login on an inaccessible machine.
2. Provision runtime secret identities and encrypted-file recipients using the
   [secret guide](../secrets/README.md). Copying a closure does not provision
   private age keys.
3. Verify connectivity and the SSH host key through a trusted channel. For CI,
   update [`.github/ssh_known_hosts`](../.github/ssh_known_hosts) after verification;
   do not disable strict host-key checking to make deployment pass.
4. For CI, configure the secrets, private-network access and environment
   protections described in [development](development.md#continuous-integration).
   The workflow's network join requires the target already be reachable there.
5. Build the target, compare closures, and deploy deliberately:

```sh
nix run .#deploy -- --help
# Activates remotely; not an evaluation-only operation.
nix run .#deploy -- ".#${host}"
```

The generated deploy-rs activation path is also independently buildable:

```sh
nix build --no-link -L ".#deploy.nodes.\"${host}\".profiles.system.path"
```

A successful deployment is not a backup. Keep a recovery access path before
changing SSH, network or privileged-user settings. Deploy-rs activation rollback
and old system generations cannot reverse database migrations, deleted data,
rotated external credentials or infrastructure changes. Retain required
snapshots/backups and consult [services](services.md) and
[Terranix](../terranix/README.md) for those boundaries.

## Troubleshooting

- **Missing new module/output:** check its discovery entrypoint and Git tracking;
  packages require explicit registration. Do not add manual imports everywhere
  to compensate for a misunderstood scanner.
- **JSON function error:** select attribute names or a serializable leaf, not a
  whole system value.
- **Unsupported build platform:** evaluation and execution platforms differ;
  choose a compatible builder rather than changing the host's target platform.
- **Secret activation failure:** check the target identity, recipients, runtime
  path/ownership and service ordering. Never debug by logging plaintext values.
- **Deployment authentication/host-key failure:** verify the effective node,
  routing, public-key authorization and trusted host key; do not weaken SSH or
  sudo policy as a workaround.
- **Unexpected closure growth:** separate explicitly configured packages from
  dependencies, then use `nix why-depends` and a before/after comparison.
