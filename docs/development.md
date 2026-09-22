# Development and standards

[Project overview](../README.md) · [Operations](operations.md) ·
[Packages](../packages/README.md)

## Development environment

From the repository root:

```sh
nix develop
```

The default shell is defined in [`flake.nix`](../flake.nix). It installs the
pre-commit hook, exposes the configured checking tools and development utilities,
and sets `SOPS_AGE_KEY_FILE` to the user's conventional SOPS age identity file.
It does not generate that file, decrypt secrets, install the local application
packages, or activate a host. See [secrets](../secrets/README.md) for identity
bootstrap. With direnv installed, reviewing [`.envrc`](../.envrc) and running
`direnv allow` activates the same environment on entering the checkout.

Discover shell names for a system returned by the root guide's package discovery:

```sh
system='SYSTEM_FROM_PACKAGES_OUTPUT'
nix eval --json ".#devShells.${system}" --apply builtins.attrNames
```

Infrastructure shells are separate from the default development shell; follow
[Terranix](../terranix/README.md) rather than assuming the default shell provides
an authenticated infrastructure CLI.

## Configuration conventions

These conventions follow the composition in
[`flake-module.nix`](../flake-module.nix) and the existing modules:

- **Choose the owning layer.** Hardware and machine-specific enablement belong
  in a host; shared system policy belongs in the appropriate platform module;
  user application settings belong in Home Manager; build logic belongs in a
  package. Infrastructure resources belong in Terranix, not shell commands hidden
  in system activation.
- **Understand automatic imports.** Every discovered reusable platform module is
  imported. A new unconditional definition is a change to all relevant hosts or
  users. Prefer `lib.mkEnableOption`, typed `lib.mkOption` definitions and
  `lib.mkIf config.my.<feature>.enable` for optional features. This is not a
  blanket ban on unconditional shared policy: review its intended scope.
- **Declare options separately from conditional configuration.** Keep imports
  unconditional where they establish options. Do not conditionally import a
  module based on the configuration it helps define. Use `lib.mkMerge` when
  combining independent conditional configuration blocks.
- **Use the existing namespace and arguments.** Extend the relevant `my.*`
  feature rather than introducing another activation convention. Read the
  platform module guide before assuming an argument such as `secretModules` or
  `self` exists. Use the injected `pkgs`/`unstable` sets rather than an unpinned
  channel or ad hoc fetch in a module.
- **Keep directory discovery unambiguous.** Prefer `<name>/default.nix` when a
  module has supporting files. Import those files explicitly from the
  entrypoint. Do not create both `<name>.nix` and `<name>/default.nix`. User
  entrypoints have additional platform-specific rules; see [users](../users/README.md).
- **Respect module merging.** Use `lib.mkDefault` for deliberately overridable
  defaults. Reserve `lib.mkForce` for intentional policy overrides, not to hide
  a conflict. Host desktop/work flags already forcibly propagate into embedded
  Home Manager configurations.
- **Treat persistence as a compatibility contract.** Preserve installed hosts'
  `system.stateVersion`, users' `home.stateVersion`, persistent service paths,
  and account UID/GID ownership unless performing a deliberate migration.
  Updating a package/input is not a reason to bump a state version.
- **Keep credentials out of the store.** Use encrypted SOPS files and runtime
  paths. Nix strings, derivations, generated infrastructure JSON and activation
  scripts are not private storage. Do not read plaintext secrets at evaluation
  time. Follow the [secret guide](../secrets/README.md).
- **Keep sources reproducible.** Commit input lock changes intentionally; use
  the package's existing source/lock/hash workflow. Adding a package is explicit
  registration, not module discovery. See [packages](../packages/README.md).

The module system enforces declared types and assertions, while review enforces
placement and scope. The formatter and static checks below do not prove that a
new feature is safely gated or that a state migration is correct.

## Formatting and checks

The root flake configures treefmt with Nix formatting, ShellCheck, Prettier and
Go formatting. Pre-commit additionally enables deadnix, statix, flake-checker,
actionlint, AWS credential detection, private-key detection and zizmor's GitHub
Actions audit. Their configuration in [`flake.nix`](../flake.nix), rather than a
manually maintained tool-version table, is authoritative.

```sh
# Format using the repository's flake formatter.
nix fmt

# In nix develop: run the configured hooks over tracked files.
pre-commit run --all-files

# Evaluate standard outputs for all declared systems, without building checks.
nix flake check --all-systems --no-build --keep-going

# Evaluate and build checks for the local supported system.
nix flake check
```

Formatting can change files. Review those changes. Local checks do not substitute
for building the affected host/package on a compatible platform. Conversely,
`--no-build` is evaluation only, not evidence that a derivation builds or a
service starts. See [operations](operations.md) for targeted build and comparison
commands and [HttpCraft development](../packages/httpcraft/docs/nix_usage.md)
for application-specific scripts and its Nix smoke check.

### New files and Git-backed flakes

Nix's Git-backed flake source includes tracked files and their working-tree
changes, but excludes ordinary untracked files. A newly created module, host,
package source or template can therefore appear missing until it is added to
the index. Review the file, then add the intended paths explicitly before
running normal `.#...` validation; avoid indiscriminate staging of secret files.
An explicit `path:` flake reference includes local files differently and is not
proof that a normal Git-backed build sees them.

## Updating inputs

Input URLs and `follows` relationships live in [`flake.nix`](../flake.nix);
resolved revisions live in [`flake.lock`](../flake.lock). Discover input names:

```sh
nix flake metadata --json
```

Update a selected input or deliberately update the complete lock:

```sh
input='INPUT_NAME_FROM_METADATA'
nix flake update "$input"

# Broader change: updates all inputs.
nix flake update
```

Review lock changes, run the relevant checks, build affected outputs, and compare
closures before switching. Following inputs can move together; do not assume a
single input update changes only one package. The existing automation opens a
lock-update pull request on its scheduled or manually dispatched run; its
schedule, labels and permissions live in
[`update-flake-lock.yml`](../.github/workflows/update-flake-lock.yml).

## Continuous integration

CI matrices are generated from flake outputs; they are not hand-maintained host
lists. Inspect what the current configuration selects:

```sh
nix eval --json .#githubActions.matrix
nix eval --json .#githubActions.dix.matrix
nix eval --json .#githubActions.deploy.matrix
```

| Workflow                                                   | Actual responsibility                                                                                                                                                                                                                                                               |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Evaluation](../.github/workflows/nix-eval.yml)            | On pull requests, evaluates standard outputs without building; additionally forces Darwin toplevel derivation paths and custom infrastructure/deploy/CI outputs.                                                                                                                    |
| [Checks](../.github/workflows/nix-github-actions.yml)      | On pull requests, builds the generated `githubActions.matrix` check attributes. The matrix currently selects a subset of package systems in `flake-module.nix`, not every supported system.                                                                                         |
| [Closure differences](../.github/workflows/dix.yml)        | On pull requests, compares base/head closures selected by `my.dix.enable`, saves artifacts, and attempts a sticky PR comment. It supports NixOS, Darwin and any separately provided standalone Home Manager outputs; this repository does not generate standalone homes from users. |
| [Deployment](../.github/workflows/deploy.yml)              | On the configured deployment branch and permitted manual runs, builds the selected activation closures, joins the private network, and deploys through SSH in the workflow's protected environment. This is a separate workflow, not an explicit dependency on the PR check jobs.   |
| [Lock updates](../.github/workflows/update-flake-lock.yml) | Proposes input lock updates; it does not automatically demonstrate runtime compatibility.                                                                                                                                                                                           |

Read workflow triggers and protections in the linked files instead of assuming
all checks run on every event. The closure-diff matrix comes from the PR head:
new configurations have no prior closure, and removed/disabled entries are not
a complete removal report. Comment permissions may be restricted for forks;
the build logs and artifacts remain the diagnostic starting point.

Deployment requires both `my.deploy-rs.enable` and
`my.deploy-rs.githubActions.enable` on the selected NixOS host. CI additionally
requires the workflow's `TAILSCALE_AUTHKEY` and `DEPLOY_SSH_KEY` secrets, a trusted
host key in [`.github/ssh_known_hosts`](../.github/ssh_known_hosts), and appropriate
repository/environment permissions. Those secret names are the workflow API,
not literal credentials. [Operations](operations.md#remote-deployment) covers
bootstrap and the root-equivalent trust granted to the deployment account.

## Before proposing a change

- Confirm which hosts/users inherit the changed module, including disabled
  feature evaluation and platform-specific imports.
- Run the targeted evaluation/build or application check appropriate to the
  change; do not infer runtime health from a successful evaluation.
- For dependency or system-package changes, compare the relevant closures.
- For services/infrastructure, review persistent data, credentials, access
  control, and rollback limitations before activation.
- Update the owning documentation when a contract changes. Use discovery commands
  and explicit placeholders instead of copying current deployment values.
