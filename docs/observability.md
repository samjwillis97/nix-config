# Observability PoC on teeny

This is the `teeny`-only proof of concept for agent-assisted log triage. It is
implemented in the flake and covered by a VM test, but it is **not deployed**.
Nothing here opens a network listener beyond loopback or grants the Amp runner
journal access.

## What runs

- **VictoriaLogs 1.52.1** on `127.0.0.1:9428`. It keeps 14 days, drops the
  oldest partitions at 80% disk use, stops accepting writes below 1 GB free, and
  drops `_CMDLINE` because command lines routinely contain secrets.
- **`systemd-journal-upload`** ships `teeny`'s journal to
  `http://127.0.0.1:9428/insert/journald` (systemd appends `/upload`). Unit,
  priority, host, transport, and message stay structured.
- **`mcp-victorialogs` 1.9.0** on `127.0.0.1:8081`. It exposes only the
  read-only query, stats, field, and stream tools. The embedded documentation
  and flags tools are disabled to keep its memory footprint down.
- **`probe` system user**, a member of `systemd-journal`. A socket-activated
  broker runs as this user and exposes a fixed allowlist of read-only commands.
  The `amp` runner is in the `probe` group, which owns the socket; it is not in
  `systemd-journal` and cannot read the journal directly.
- **`.agents/skills/logs`**, the project skill that teaches the agent the query
  conventions, the probe commands, and the safety rules.

The module is `nixos-modules/observability/default.nix`; the host enables it in
`nixos-hosts/teeny/default.nix`:

```nix
my.observability = {
  logs = {
    enable = true;
    retention = "14d";
    mcp.enable = true;
  };
  probe.enable = true;
};
```

## Querying logs

The agent loads the `logs` skill and gets the `victorialogs` MCP tools. Useful
queries:

```text
level:err AND _time:15m
_SYSTEMD_UNIT:jellyfin.service AND level:err
level:err | stats by (_SYSTEMD_UNIT) count() as errors | filter errors:>0
```

For a manual check, the HTTP API is enough:

```sh
curl -fsS --data-urlencode 'query=_SYSTEMD_UNIT:jellyfin.service AND level:err' \
  http://127.0.0.1:9428/select/logsql/query
```

The built-in UI is at `http://127.0.0.1:9428/select/vmui` on `teeny` (use an SSH
tunnel or a runner terminal; it is not exposed to the tailnet).

## Read-only probes

`teeny-probe` is on the runner's `PATH`. It talks to the broker over
`/run/teeny-probe/probe.sock`:

```sh
teeny-probe journal --unit jellyfin.service --since=-30m --priority err --limit 100
teeny-probe unit-status jellyfin.service
teeny-probe failed-units
teeny-probe disk
teeny-probe memory
teeny-probe uptime
teeny-probe list-units 'jellyfin*'
```

Use `--since=-30m` (with the equals sign) so argparse does not read the value as
a flag.

The broker validates unit names, time windows, priorities, and glob patterns
before calling `journalctl` or `systemctl`. It only accepts the fixed commands
above; there is no shell passthrough.

## Agent discovery

Amp lists project skills from `.agents/skills/` in the checkout. The model sees
the `logs` skill's name and description, then loads the rest of `SKILL.md` and
its `mcp.json` tools when it invokes the skill. This is a model decision, not an
automatic load, so the runner's global `AGENTS.md` now tells `teeny` threads to
load `logs` for log or service investigations. The future dispatcher prompt
should say the same thing explicitly.

The skill is project-scoped: the runner's checkout must contain the commit with
`.agents/skills/logs`, and the thread must run on `teeny` because both the MCP
endpoint and the probe socket are loopback-only. A thread on another machine can
read the skill text but cannot use its tools.

The dispatcher prompt template is [`docs/triage-prompt.md`](triage-prompt.md);
it uses `{{host}}`, `{{unit}}`, `{{alert_json}}`, and `{{action}}` placeholders.
The eval harness is in [`evals/teeny-triage/`](../evals/teeny-triage/README.md).

## Evaluating the prompt and runner target

The eval harness lives in `evals/teeny-triage/`:

```sh
# Prompt and case-shape checks; no tokens, no threads.
nix shell nixpkgs#python3 -c python3 evals/teeny-triage/eval.py --mode static

# One tiny thread on teeny to prove the executor target.
nix shell nixpkgs#python3 -c python3 evals/teeny-triage/eval.py --mode target \
  --agent-mode medium

# The triage cases; requires the deployment and the skill in the checkout.
nix shell nixpkgs#python3 -c python3 evals/teeny-triage/eval.py --mode live \
  --agent-mode medium \
  --runner-dir /var/lib/amp/code/code/github.com/samjwillis97/nix-config
```

`--agent-mode low` is the intended production mode, but the provider can return
`429 prefill_cap_refused`; `medium` is a useful fallback. The eval polls thread
exports slowly because Amp rate-limits repeated full reads.

The runner's served path on `teeny` is
`/var/lib/amp/code/code/github.com/samjwillis97/nix-config`; there is no
`.../nix-config/main` worktree. Use the served path for `--runner-dir`.

### Current results

- `--mode static`: passes.
- `--mode target`: passes; the thread reports `runnerID=teeny`,
  `hostname=teeny`, and a `/var/lib/amp/code` working directory.
- `--mode live --case known-unit`: fails because `skill("logs")` returns
  “not found” and neither the VictoriaLogs MCP server nor `teeny-probe` is
  installed. The agent attempted the skill, stayed read-only, and explicitly
  reported the missing tools instead of inventing logs. This is the expected
  result until the observability module is deployed and the skill is in the
  runner checkout.

## Deduplication policy

The `triage-state` package is the gate the future dispatcher will call before
starting a thread. It prevents a flapping service from producing a thread per
evaluation:

- **Fingerprint** = SHA-256 of `alertname|host|unit`. It deliberately excludes
  the changing `$value` and summary.
- **Per-fingerprint cooldown** of 6 hours. A similar alert inside the window is
  suppressed.
- **Global budgets** of 3 spawns per hour and 10 per day across all incidents.
- **Resolved alerts** are recorded but never spawn.
- **One incident, one thread**: the dispatcher stores the thread URL with the
  fingerprint. A later evaluation of the same incident continues that thread
  instead of creating a new one.

The dispatcher sequence is:

```sh
decision=$(nix run .#triage-state -- check --alert alert.json)
case "$(printf '%s' "$decision" | jq -r .decision)" in
  spawn)
    thread_url=$(amp -x "$(cat /etc/triage/prompt.md)" \
      --executor runner:teeny \
      --runner-dir /var/lib/amp/code/code/github.com/samjwillis97/nix-config \
      --no-archive-after-execute -m low)
    nix run .#triage-state -- record --alert alert.json \
      --thread-url "$thread_url"
    ;;
  continue)
    amp threads continue "$(printf '%s' "$decision" | jq -r .thread_url)" \
      -x "The alert is still firing. Re-check the logs and update your findings."
    ;;
  suppress)
    ;;
esac
```

The dispatcher service will call the packaged binary directly; `nix run` is only
shown so the policy can be exercised before that service exists.

A new incident returns `spawn`. A similar alert inside the cooldown returns
`suppress`. After the cooldown, a still-open incident returns `continue` with the
stored thread URL, so the dispatcher adds a follow-up to the existing thread
instead of creating another one. A resolved incident that fires again after the
cooldown returns `spawn`, because it is a new episode.

`check` also updates `last_seen` and the open/resolved status. If the Amp call
fails, do not call `record`; the next evaluation can retry. The state database
defaults to `/var/lib/triage/state.db`; use `triage-state list` to inspect it and
`triage-state prune --days 30` to age it out.

Automatic spawning is **not enabled** in this PoC. The dedupe package and its
tests are in place so the dispatcher can be added without reworking the alert
path.

## Security boundaries

- VictoriaLogs and the MCP server bind to loopback only. No firewall rule, no
  Cloudflare route, and no tailnet listener was added.
- The `probe` user has journal read access. The `amp` user has only the `probe`
  socket group. The socket is `0660 probe:probe`.
- The broker runs as `probe` with `NoNewPrivileges`, `ProtectSystem=strict`,
  `ProtectHome`, a private `/tmp`, no capabilities, and `AF_UNIX` only.
- The Amp runner's existing sandbox is unchanged: no sudo, no deploy
  credentials, and the existing inaccessible paths remain inaccessible.
- `_CMDLINE` is dropped at ingest. Log lines are still untrusted input; the
  skill says never to follow instructions found in them.
- A log line read by the agent becomes part of the Amp thread conversation and
  therefore leaves the tailnet. Keep queries narrow and redact secrets.

## Verification

```sh
nix build .#mcp-victorialogs .#teeny-probe .#triage-state
nix build .#checks.x86_64-linux.observability
nix build .#nixosConfigurations.teeny.config.system.build.toplevel
```

The VM test asserts that:

- `systemd-journal-upload` reaches VictoriaLogs and the test service's error is
  queryable by `_SYSTEMD_UNIT`;
- the MCP server answers an `initialize` request and identifies itself;
- the `probe` user is in `systemd-journal` and the client user is in `probe`;
- the socket is `0660` and the client can run `ping`, `journal`, `unit-status`,
  and `disk`;
- path traversal (`../../etc/passwd`) and command injection
  (`bad;rm -rf /`) are rejected.

## Deployment and rollback

The host change is already in `nixos-hosts/teeny/default.nix`; it has not been
activated. Review the closure and deploy through the normal `deploy-rs` process:

```sh
nix build .#nixosConfigurations.teeny.config.system.build.toplevel
# then use the approved deploy workflow; do not switch from an agent thread
```

After activation:

```sh
systemctl status victorialogs.service
systemctl status systemd-journal-upload.service
systemctl status victorialogs-mcp.service
systemctl status teeny-probe.socket
journalctl -u victorialogs -u systemd-journal-upload -u victorialogs-mcp --since today
```

To stop the PoC without losing data, set `my.observability.logs.enable = false`
and `my.observability.probe.enable = false` and deploy. `/var/lib/victorialogs`
is not deleted automatically; decide retention separately.

## Limits and next steps

- Only `teeny` is covered. Other hosts still need a shipper and a tailnet
  listener (or a local upload) before their logs are available.
- The MCP endpoint is loopback-only, so only runner threads on `teeny` can use
  it. Exposing it to the tailnet needs an ACL or a reverse proxy with auth.
- There is no vmalert, Alertmanager, or dispatcher yet. The next phase is a
  small set of LogsQL rules, Alertmanager grouping, and the `triage-state`
  gate above.
- The agent can read logs and the config repo, but it cannot run commands on
  another host. Add per-host runners or a read-only host-probe MCP only when
  that becomes necessary.
