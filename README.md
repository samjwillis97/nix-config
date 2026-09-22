# nix-config

A flake-parts configuration for NixOS, nix-darwin, embedded Home Manager,
reusable packages, development templates, and Cloudflare infrastructure managed
through Terranix and OpenTofu.

This documentation describes **how configuration is composed and changed**, not
an inventory of machines, accounts, package versions, or infrastructure IDs.
Discover current values from the flake and source files rather than copying a
previous deployment's values.

## Start here

1. Install Nix with the `nix-command` and `flakes` experimental features enabled.
2. Open a checkout and run `nix develop`. Alternatively, review [`.envrc`](.envrc)
   and run `direnv allow` if you use direnv. Entering the development shell
   installs the repository's pre-commit hook and sets its SOPS identity-file
   location; it does not create an identity or grant secret access.
3. Read [development and standards](docs/development.md) before editing.
4. Discover the configuration or package you intend to change, then follow its
   guide below. Building and evaluating do not activate a system; switching,
   deploying, and applying infrastructure do.

Commands assume the repository root unless a guide says otherwise. Uppercase
values such as `HOST_OUTPUT` in variable assignments are placeholders to replace,
not existing resources. Commands using `jq` require it on your `PATH`; do not
assume every tool mentioned in a guide is included in the development shell.

## Structure and ownership

| Path                                       | Responsibility                                                                                                              | Guide                                                  |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| [`flake.nix`](flake.nix)                   | Input declarations, supported package systems, explicit packages/apps, infrastructure wrapper, development tools and checks | [Development](docs/development.md)                     |
| [`flake.lock`](flake.lock)                 | Resolved input revisions and hashes                                                                                         | [Updating inputs](docs/development.md#updating-inputs) |
| [`flake-module.nix`](flake-module.nix)     | Filesystem discovery, system composition, exported modules, templates, deployment and CI matrices                           | This overview                                          |
| `nixos-hosts/`                             | Machine-specific NixOS choices and hardware configuration                                                                   | [Add a NixOS host](nixos-hosts/README.md)              |
| `darwin-hosts/`                            | Machine-specific macOS choices                                                                                              | [Add a Darwin host](darwin-hosts/README.md)            |
| `nixos-modules/`                           | Shared NixOS policy and opt-in features                                                                                     | [Add a NixOS module](nixos-modules/README.md)          |
| `darwin-modules/`                          | Shared nix-darwin policy and opt-in features                                                                                | [Add a Darwin module](darwin-modules/README.md)        |
| `home-modules/`                            | Shared Home Manager policy and opt-in user features                                                                         | [Add a home module](home-modules/README.md)            |
| `users/`                                   | Platform-specific accounts and per-user home configuration                                                                  | [Add a user](users/README.md)                          |
| `groups/`                                  | NixOS groups and declared membership                                                                                        | [Add a group](groups/README.md)                        |
| `packages/`                                | Local derivations, application sources, and editor composition                                                              | [Packages](packages/README.md)                         |
| `overlays/`                                | Package-set integration used by host configurations                                                                         | [Overlays](overlays/README.md)                         |
| `templates/`                               | Flake templates copied into other projects                                                                                  | [Templates](templates/README.md)                       |
| `secrets/` and [`.sops.yaml`](.sops.yaml)  | Encrypted data, runtime declarations, and recipient policy                                                                  | [Secrets](secrets/README.md)                           |
| `terranix/`                                | Infrastructure resource definitions                                                                                         | [Terranix and Cloudflare](terranix/README.md)          |
| [`.github/workflows/`](.github/workflows/) | Evaluation, build, closure-diff, deployment and dependency-update automation                                                | [CI](docs/development.md#continuous-integration)       |

For day-to-day work, see [build, deploy, inspect and compare closures](docs/operations.md)
and [stateful services and networking](docs/services.md).

## How composition works

`flake.nix` uses flake-parts and imports `flake-module.nix`. The latter scans
specific directories to build the flake's configuration outputs:

- A regular `<name>.nix` file or `<name>/default.nix` directory entry is a module
  named `<name>`. Scanning is one level deep; nested files need an entrypoint's
  explicit `imports`. Avoid two entries that produce the same name.
- The reusable module directories are **imported in full** into every matching
  platform configuration. Their `default.nix` files are ordinary discovered
  modules, not special switches or lists that register sibling modules. There
  is no `importDefault` flag in the composition layer.
- An unconditional definition therefore affects every host or home in that
  module's scope. Optional features declare typed options, conventionally under
  `my`, and guard configuration with `lib.mkIf`. See the module guides for
  complete examples and available arguments.
- Each discovered host receives those shared modules, upstream integrations,
  overlays, and its own host module. NixOS output names also set
  `networking.hostName`; Darwin output names do not automatically set it.
- User and group files are **not another universally imported module directory**:
  platform user modules select accounts and corresponding home definitions;
  the NixOS group module imports discovered group definitions. Read their guides
  before adding entries. User directory entrypoints additionally include
  `home.nix` and `darwin.nix` for their respective discovery passes.
- Home Manager is integrated into NixOS and Darwin configurations, with its
  configuration gated by `my.home-manager.enable`. Its upstream module is
  imported unconditionally so its options exist. Shared home modules receive
  the host's desktop/work flags. The current composition does not create
  standalone `homeConfigurations` from the `users/` directory.
- Packages are explicitly registered under `perSystem.packages` in `flake.nix`;
  merely adding a package directory does not export it. Templates instead use
  the directory scanner with `flake.nix` as their directory entrypoint.
- Derived outputs select enabled configurations: `deploy.nodes` for deploy-rs,
  `cloudflareHosts` for infrastructure, and `githubActions` for CI matrices.
  Their guide explains each opt-in; adding a host is not sufficient to enable
  all automation.

## Discover the current configuration

These commands list output names without evaluating entire system values as JSON:

```sh
nix eval --json .#nixosConfigurations --apply builtins.attrNames
nix eval --json .#darwinConfigurations --apply builtins.attrNames
nix eval --json .#packages --apply builtins.attrNames
nix eval --json .#templates --apply builtins.attrNames
nix eval --json .#nixosModules --apply builtins.attrNames
nix eval --json .#darwinModules --apply builtins.attrNames
nix eval --json .#homeModules --apply builtins.attrNames
```

Select a package system from that output, then inspect its exported packages and
apps; do not confuse a system identifier with a host's configuration name:

```sh
system='SYSTEM_FROM_PACKAGES_OUTPUT'
nix eval --json ".#packages.${system}" --apply builtins.attrNames
nix eval --json ".#apps.${system}" --apply builtins.attrNames
```

`nix flake show --all-systems` gives a broader overview, but custom outputs may
appear as `unknown`; this does not imply they are missing. Inspect those outputs
directly, for example `nix eval --json .#deploy.nodes --apply builtins.attrNames`.
Complete NixOS/Darwin configurations contain functions and cannot be serialized
as JSON. Select attributes such as `config.system.stateVersion` or a derivation's
`drvPath` instead; [operations](docs/operations.md) shows the relevant leaves.

## Documentation boundaries

The root and directory guides describe this repository's Nix contracts. Local
applications can have their own development and user documentation, linked from
[packages](packages/README.md). They are not automatically shared Nix policies.
When changing behavior, update the owning guide and any affected examples;
keep deployment identities, version pins and enabled-resource lists in their
configuration sources, not copied into prose.
