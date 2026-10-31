# Buildkite agents on teeny

This runbook covers the self-hosted Buildkite agents on `teeny`, their token,
and the host boundary they run in. The feature lives in
[`nixos-modules/buildkite/default.nix`](../nixos-modules/buildkite/default.nix),
which wraps the NixOS `services.buildkite-agents` module. Host-specific
enablement and tags live in
[`nixos-hosts/teeny/default.nix`](../nixos-hosts/teeny/default.nix).

## Current state

`my.buildkite.enable = true` on `teeny` with one agent instance,
`agents.teeny`. It registers with the `queue=linux-selfhosted` and `host=teeny`
tags and runs as `buildkite-agent-teeny.service` under the locked system user
`buildkite-agent-teeny`.

The target cluster must contain a **self-hosted** queue with the key
`linux-selfhosted`. A Buildkite hosted queue cannot accept this agent, and the
agent does not register until that queue exists. Create the queue in the
Buildkite cluster before deploying the host.

The encrypted file `secrets/buildkite/teeny.yaml` contains a placeholder token
in the `buildkite-agent-token` key. **Replace it before deploying.** Until then
the agent cannot authenticate to Buildkite.

## Provision the agent token

1. In the target Buildkite organization, open the Agents page and create an
   agent token with the narrowest scope available. Do not paste the token into
   chat, a Nix file, a command line, an issue, or a shell variable.
2. From the repository root in the development shell, edit the encrypted file:

   ```sh
   sops edit secrets/buildkite/teeny.yaml
   ```

   Replace the placeholder value of `buildkite-agent-token` and save. The
   existing `^secrets/(.*/)?teeny[.]yaml$` creation rule already grants the
   `teeny` system identity and the editor identity; do not add a broader
   recipient.

3. Verify the file without decrypting it:

   ```sh
   sops filestatus secrets/buildkite/teeny.yaml
   ```

4. Build the host without switching it:

   ```sh
   nix build --no-link '.#nixosConfigurations.teeny.config.system.build.toplevel'
   ```

At activation, sops-nix installs the value at
`/run/secrets/buildkite-agent-token`, owned `root:buildkite-agents` with mode
`0440`. The agent's pre-start writes `buildkite-agent.cfg` into its `0700` home
with mode `0600`, and a change to the secret restarts
`buildkite-agent-teeny.service`.

## Tags and queues

The agent advertises the tags configured under `my.buildkite.agents.<name>.tags`.
Pipelines target it with `queue=linux-selfhosted` or `host=teeny`. The queue tag
must match a self-hosted queue in the same Buildkite cluster; it is not a
Buildkite hosted queue. Add tags in the host configuration rather than editing
the generated agent config on the machine, and inspect the effective values
before changing a pipeline:

```sh
nix eval --json '.#nixosConfigurations.teeny.config.my.buildkite'
```

## Operations

These are administrator operations, not actions available to the agent account:

```sh
sudo systemctl status buildkite-agent-teeny.service
sudo journalctl -u buildkite-agent-teeny.service --since today --no-pager
sudo systemctl restart buildkite-agent-teeny.service
```

The upstream unit restarts on failure and waits for
`sops-install-secrets.service` before starting. A secret change restarts the
unit automatically after the next deployment.

## Resource and trust boundary

- `teeny` keeps the Nix daemon at `max-jobs = 1` and `cores = 2`, and weights the
  daemon below interactive services. Additional agent processes do not add CPU,
  memory, or build parallelism; they only allow more concurrent Buildkite jobs,
  which still contend for the same daemon and network.
- The agent runs directly on the host. It shares the Nix daemon, the Nix store,
  the network, and the service user's filesystem view. This is not a VM or
  container sandbox; there is no per-job isolation.
- Pipeline code runs as `buildkite-agent-teeny` and can read that account's
  Buildkite token, its `0600` agent configuration, its home, and anything else
  the account can access. Only run pipelines you trust to act as this account.
  The token is a credential: it can register agents and receive jobs.
- The `buildkite-agents` group exists only to let agent accounts read the shared
  token file. Do not add other users to it.
- The agent has no sudo, wheel, or Nix trusted-user role. Do not add them
  without a separate review. It also has no ingress route, firewall listener, or
  public port; it only makes outbound connections.
- The agent's home is `/var/lib/buildkite-agent-teeny` and contains build
  checkouts, logs, and the generated configuration. The repository does not
  back it up. Preserve or remove it deliberately; it is not disposable state for
  a normal restart or upgrade.

## Rotation, stop, and removal

To rotate a suspected or expired token, revoke it in Buildkite, edit
`secrets/buildkite/teeny.yaml` with `sops edit`, review the ciphertext diff, and
deploy through the approved process. The SOPS declaration restarts the unit when
the value changes.

To stop new jobs during an incident:

```sh
sudo systemctl stop buildkite-agent-teeny.service
```

For a persistent disable, set `my.buildkite.enable = false` in the host
configuration and deploy it. Disabling the feature also stops declaring the
secret, so the `buildkite-agents` group is not left behind. Do not delete
`/var/lib/buildkite-agent-teeny` as part of a stop or restart. The encrypted
token file and the host's secret-module import can then be removed in a separate
reviewed change.
