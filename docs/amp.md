# Browser-controlled Amp runner on teeny

This runbook describes the opt-in Amp remote runner for `teeny`. Amp's browser
client is the control plane; the host runs the pinned Amp CLI as an unprivileged
systemd service. The optional Desktop tab uses a private headless Wayland desktop,
not the host's physical display. There is no public runner port, SSH workflow,
Amp Portal support, or per-task VM.

## Rollout status and prerequisites

The host configuration enables the CLI, runner and virtual desktop through
`my.amp.enable`, `my.amp.runner.enable`, and
`my.amp.runner.desktop.enable`. The encrypted credential file exists and
the host imports the Amp secret module. These source settings do not establish
which generation is deployed: desktop enablement requires a separately approved
deployment and runner restart.

The isolated VM test verifies credential
staging, filesystem restrictions, GitHub credential-helper scoping, direnv
execution, and Nix-daemon access to an existing store path. An exploratory VM build probe returned a fresh store path that the service
process could not read. Therefore, a fresh Nix build and `nix develop` from
inside the hardened service are **not validated by that coverage**. The checked-in VM test
does not claim to prove that project builds work.

Deployment and live browser, GitHub, or reboot tests require separate
operational approval. No command in this runbook authorizes a switch or a live
smoke test.

## Architecture and limits

- The service is `amp-runner.service`, owned by the dedicated `amp` system user
  and group. Its persistent home and workspace are `/var/lib/amp` and
  `/var/lib/amp/code`; service state and worktrees survive restart and upgrades.
- Amp is launched without a TUI using runner ID `teeny`, browser Terminal
  support, and directory discovery rooted at the code directory (depth 4).
  Directory discovery fits checkouts such as
  `code/github.com/owner/repository/branch`.
- The `amp` account has no sudo, wheel, deployment, or Nix trusted-user role.
  The unit uses a locked account, systemd credentials, private temporary files,
  `ProtectHome`, `ProtectSystem=strict`, no new privileges, no capabilities, and
  inaccessible paths for host secrets and service data.
- GitHub access is an environment token scoped to selected repositories. Every
  Amp thread running on this host shares the same account, credentials, Nix
  daemon, filesystem boundary, and network access. Worktrees isolate file
  changes, not processes or credentials. This is not a VM or network sandbox.
- When desktop support is enabled, Amp starts its own headless labwc compositor
  and Waymote streaming processes inside the existing service sandbox. Threads
  inherit the desktop display variables. It does not capture a physical display
  or enable Amp Portals. Amp and GitHub, Nix caches, and repository dependencies
  require outgoing connectivity.
- `teeny`'s daemon concurrency is set to `max-jobs = 1` and `cores = 2`, with
  lower CPU/I/O weights for the runner and daemon. Those daemon limits also
  apply to administrative builds. `cores` is a scheduling hint, not a hard CPU
  cap. No arbitrary memory ceiling is configured; tune optional service memory
  and task limits only after observing real headroom.

## Credentials and final host enablement

The SOPS module declares two independent keys in the host-specific encrypted
file `secrets/amp/teeny.yaml`:

- `amp-api-key`: a long-lived Amp access token used as `AMP_API_KEY` (not a
  short-lived browser login token);
- `amp-github-token`: a GitHub fine-grained token used as `GH_TOKEN`, limited to
  the repositories selected for this runner. Grant repository contents
  read/write and pull requests read/write only when those actions are required.

The operator creates and edits the encrypted file locally with the configured
SOPS identity, for example `sops edit secrets/amp/teeny.yaml`. Enter the values
only into the SOPS editor; do not send them through chat, put them in Nix source,
commit plaintext, or create placeholder files. Reuse the existing
`.sops.yaml` recipient rule for `secrets/**/teeny.yaml`; do not add a broader
recipient. Verify the encrypted file can be decrypted by the intended host
identity without printing its values.

Only after the encrypted file exists and its keys have been verified should the
reviewed host change import `secretModules.amp`, set
`my.amp.runner.enable = true`, and point `apiKeyFile` and `githubTokenFile` at
the corresponding SOPS secret paths. The module requires both paths and the
runner ID. The host already has this wiring. Validate the enabled
configuration and build it without switching. Keep any later activation behind
separate deployment approval.

At runtime, systemd copies each source into its protected credentials directory.
The startup wrapper reads and exports the values immediately before executing
Amp. Do not add credentials to `Environment=`, `ExecStart`, Git URLs, generated
settings, shell traces, or logs. The agent process necessarily has access to
both tokens; SOPS and systemd credentials protect storage and delivery, not
against code running as the agent.

### Rotation or suspected compromise

1. Revoke the old Amp token in Amp Security Settings and the old GitHub token in
   GitHub. If compromise is suspected, revoke first; do not wait for a normal
   deployment window.
2. Create replacement credentials with the same least-privilege scopes and edit
   the encrypted SOPS file locally. Keep the two values in their separate keys.
3. Review the encrypted-file diff and secret names only. Do not print decrypted
   values or put them in a command argument.
4. Follow the approved deployment process to install the new secrets. The SOPS
   declarations request a restart of `amp-runner.service` when either secret
   changes. If the unit is not running, inspect its status before starting it.
5. Confirm service startup from status and journal metadata; never use shell
   tracing or dump the process environment. Test each credential only through
   an approved, non-production repository workflow.

## Browser-first bootstrap and repository discovery

After the service has been separately deployed and approved:

1. Sign in to the intended Amp account at `https://ampcode.com` and select the
   `teeny` runner. Do not create a new runner identity for routine restarts.
   Enable a passkey for remote interaction when available.
2. Start a bootstrap thread from the runner's code directory. Use the browser
   Terminal to create the approved owner directory and clone only an intended
   repository. For example, replace the placeholders with an explicitly
   approved repository:

   ```sh
   mkdir -p /var/lib/amp/code/github.com/<owner>
   cd /var/lib/amp/code/github.com/<owner>
   gh repo clone <owner>/<repository>
   ```

3. Confirm the checkout appears in the runner's discovered workspaces. Do not
   clone unrelated repositories merely to broaden discovery. Repository names
   and branches should fit under the configured depth.
4. Use Amp's Files and Changes views for editing and review, Terminal for shell
   commands, and Desktop for graphical programs after desktop-enabled deployment.
   Desktop does not provide a public preview URL.

The service runs in `/var/lib/amp/code`, including when no repository exists, so
an initial browser thread can bootstrap a checkout. Do not move state into
`/home/sam` or serve the entire account home.

## Virtual desktop

`my.amp.runner.desktop.enable` defaults to false and currently supports x86_64
Linux. Enabling it adds `--desktop`, labwc, wlr-randr, FFmpeg with software H.264
encoding, a D-Bus session launcher, and pinned Waymote binaries patched for NixOS.
It does not enable a system login desktop, GPU access, audio, or firewall ports.
Desktop streaming is video-only; project-specific graphical applications still
belong in their reviewed Nix development environment.

The service gets a private `/run/amp-runner` runtime directory. Amp keeps desktop
state and logs below `~/.cache/amp/runner-desktop/<runner-id>`. Amp manages the
1280×720 headless compositor and passes display variables to runner threads;
do not start another runner or set a physical display's environment variables.
All threads on a runner share this desktop. Anyone who can write to one of
those threads can see and control it: do not open secrets or sensitive sessions.
Desktop and Terminal use Amp's WebRTC/relay transport, not a public preview URL.

After an approved deployment/restart, run `amp runner desktop status`, reload the
thread and open its Desktop tab. Launch a harmless Wayland application from a
thread's reviewed Nix shell and verify it appears and accepts input. Test in a
new thread if a pre-existing thread retains old display variables. A failed
desktop should be investigated through its logs and dependency status, not by
removing the runner's filesystem restrictions.

Validate locally without switching:

```sh
nix develop -c nix build .#checks.x86_64-linux.amp-runner --no-link -L
```

The VM test exercises a headless compositor, output configuration, executable
loading and H.264 encoding inside the hardened unit. It does not connect a live
Amp client or prove WebRTC connectivity; that remains a post-deployment check.

## Git, GitHub, and worktrees

The service supplies `git` and `gh`. Its global Git configuration sets the
repository author's name/email and scopes `gh auth git-credential` to
`https://github.com`; SSH-style GitHub remotes are rewritten to HTTPS. It does
not reuse Sam's SSH key, signing key, personal Git settings, or broad
`safe.directory` configuration.

From an approved checkout, inspect the repository and current branch before
changing anything:

```sh
git status --short --branch
git remote -v
gh auth status --hostname github.com
```

`GH_TOKEN` is provided to `gh` and the Git credential helper. Never run `env`,
`set -x`, `gh auth token`, or commands that print the token. Do not embed a token
in a URL, remote, config file, command argument, patch, or worktree. Confirm
before pushing, opening a pull request, deleting a branch, or changing a
protected branch. Use draft PRs and non-production branches for an approved
smoke test.

Use a separate worktree for each concurrent task. From the main checkout, for
example:

```sh
git worktree add ../repository-task -b task/<short-description>
```

Keep worktrees below `/var/lib/amp/code` and within the discovery depth. Review
`git worktree list` before removing a worktree; do not delete one that contains
uncommitted work or an active thread. A worktree is not a security boundary:
all worktrees share the same account and credentials.

## Nix development environments

The system package list is a baseline, not a global language-toolchain
installation. Repository builds must use that repository's reviewed Nix
environment. Run commands explicitly; interactive shell hooks are not loaded
for the system service.

For a flake repository, from its root:

```sh
nix develop -c <build-or-test-command>
```

For a legacy `shell.nix` repository:

```sh
nix-shell --run '<build-or-test-command>'
```

For a repository whose `.envrc` has been reviewed and deliberately allowed:

```sh
direnv allow .
direnv exec . <build-or-test-command>
```

Do not auto-allow an arbitrary `.envrc`; inspect commands, hooks, and imported
files first. Otherwise use `direnv exec` only for an environment the operator
has already approved. If a repository has no Nix environment, inspect its
instructions and propose a project-local shell or an ephemeral `nix shell`
command rather than installing tools globally. Nix environments work only when
the project's dependencies are available/buildable for x86_64 Linux. The service
uses the shared Nix daemon and cache configuration; daemon builds can use
network access and consume host CPU, memory, disk, and store space.

**Before enabling the runner, complete the fresh Nix-build and dev-shell fixture
in the hardened service environment.** The current VM test proves daemon ping
and cached path lookup but not fresh output visibility or a working `nix
develop` shell. Do not interpret a successful `nix store ping` as build
acceptance.

## Logs, restart, and upgrades

These are administrator operations, not commands for the Amp account. Run them
only through the host's approved administrative access and change process.
They are included as reference; they do not authorize a deployment or restart.

```sh
sudo systemctl status amp-runner.service
sudo journalctl -u amp-runner.service --since today --no-pager
sudo systemctl restart amp-runner.service
```

The service restarts after an unexpected exit and starts after networking and
SOPS secret installation. A restart can interrupt an active command; persisted
threads may be continued, but a running command is not guaranteed to resume.
Check CPU and memory with host monitoring tools, free disk and Nix-store growth,
and existing media/service responsiveness before allowing heavy or parallel
builds. If memory or process use must be constrained, set the runner's optional
`memoryMax` or `tasksMax` through a reviewed host change after measuring
headroom. Do not set a speculative hard cap.

Amp's CLI is pinned through the `llm-agents` flake input. For an upgrade, update
the input through the repository's normal lock-file review, verify the new CLI
version and required runner flags, run the full module/VM checks, format and
build the affected host without switching, and review the effective systemd
unit and SOPS wiring. The runtime self-update check is disabled; do not update
the executable from inside a runner thread.

## Stop, recovery, and cleanup

To stop new agent work during an incident, an authorized administrator can stop
the service after considering any active command:

```sh
sudo systemctl stop amp-runner.service
```

For a persistent disable, make a reviewed host configuration change setting
`my.amp.runner.enable = false`, then use the approved deployment workflow. Do
not remove `/var/lib/amp` as part of a stop, disable, restart, or upgrade.

Preserve `/var/lib/amp` for recovery: it contains Amp state, configuration,
checkouts, Git worktrees, and uncommitted changes. The repository does not
configure an automatic backup for this directory. Arrange and verify a backup
that is consistent with the desired recovery point, and protect that backup as
sensitive data. Before restoring to a replacement host, restore the directory
with owner `amp:amp` and restrictive permissions, provision fresh SOPS
credentials, and validate the CLI/configuration without activating the runner.
Do not restore a stale credential in preference to rotating it.

For suspected credential disclosure, revoke both tokens at their issuing
services, stop the runner through the approved incident process, preserve logs
and worktrees for investigation, then provision new credentials through SOPS.
Do not delete evidence or assume deleting a Git worktree revokes its credentials.

## Operational acceptance checklist

After the separate deployment and live-test approvals are granted:

- Verify the runner appears in Amp's browser client without an SSH/tmux session.
- Bootstrap only an approved private test repository; verify discovery, Files,
  Changes, and browser Terminal access.
- Run a flake shell, legacy shell, and reviewed direnv fixture without relying
  on interactive hooks or globally installed language toolchains.
- With a harmless approved change, create a worktree, push a test branch, and
  open a draft PR. Confirm the GitHub token cannot access unrelated private
  repositories.
- During an agreed idle window, restart or reboot; confirm service recovery and
  persistence of threads/checkouts. Confirm no active command is assumed to
  resume automatically.
- Observe Nix build resource use, free space, store growth, and existing service
  responsiveness. Test credential rotation and stop/disable recovery without
  printing values.
- Verify the private Desktop tab and input with a harmless graphical app when
  desktop support is enabled; confirm no physical display is captured.
- Confirm there is no new ingress route, firewall port, system login desktop,
  or public application preview.
