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
- **`triage-dispatcher`**, a systemd timer that polls VictoriaLogs for
  `PRIORITY:<=3` errors, applies the dedupe gate, and starts or continues Amp
  threads on `runner:teeny`. It runs as a dedicated `triage` user with an Amp
  API credential and no journal, probe, or deploy access.
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
  triage = {
    enable = true;
    runnerDir = "/var/lib/amp/code/code/github.com/samjwillis97/nix-config";
    labels = [ "triage" ];
  };
};
```

## Querying logs

The agent loads the `logs` skill and gets the `victorialogs` MCP tools. Useful
queries:

```text
PRIORITY:<=3 AND _time:15m
_SYSTEMD_UNIT:jellyfin.service AND PRIORITY:<=3
PRIORITY:<=3 | stats by (_SYSTEMD_UNIT) count() as errors | filter errors:>0
```

For a manual check, the HTTP API is enough:

```sh
curl -fsS --data-urlencode 'query=_SYSTEMD_UNIT:jellyfin.service AND PRIORITY:<=3' \
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
automatic load, so the runner's global `AGENTS.md` and the dispatcher prompt
both tell `teeny` threads to load `logs` for log or service investigations.

The skill is project-scoped: the runner's checkout must contain the commit with
`.agents/skills/logs`, and the thread must run on `teeny` because both the MCP
endpoint and the probe socket are loopback-only. A thread on another machine can
read the skill text but cannot use its tools. After deploying this change,
refresh the runner checkout to the merged commit; the dispatcher prompt has a
read-only `curl`/`teeny-probe` fallback, but the MCP tools only load with the
skill.

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

The dispatcher defaults to `--mode medium`; `low` can return
`429 prefill_cap_refused`. The eval polls thread exports slowly because Amp
rate-limits repeated full reads.

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
- `checks.x86_64-linux.observability` passes, including a fake-Amp dispatcher
  run that spawns one thread and does not spawn again inside the cooldown.

## Automatic dispatch

A systemd timer runs `triage-dispatcher` after each completed run (one minute by
default). Each run queries VictoriaLogs for `PRIORITY:<=3` journal errors grouped
by host and systemd unit over the configured window (five minutes by default).
Units with at least the threshold (five errors by default) become alerts.

Before any Amp call, the dispatcher calls `triage-state check`; after a
successful spawn it calls `record` with the thread URL. The gate prevents a
flapping service from producing a thread per evaluation:

- **Fingerprint** = SHA-256 of `alertname|host|unit`. It deliberately excludes
  the changing `$value` and summary.
- **Per-fingerprint spawn cooldown** of 6 hours. A similar alert inside the
  window is suppressed.
- **Continue cooldown** of 6 hours. A long-running incident gets at most one
  follow-up per window instead of a new turn on every poll.
- **Global budgets** of 3 spawns per hour and 10 per day across all incidents.
- **Resolved alerts** are recorded but never spawn. If the same unit fires
  again after the cooldown, it becomes a new episode and can spawn a new thread.
- **One incident, one thread**: the dispatcher stores the thread URL with the
  fingerprint. A later evaluation of the same incident continues that thread
  instead of creating another one.

The dispatcher renders [`docs/triage-prompt.md`](triage-prompt.md) with the
alert labels and JSON, then runs the equivalent of:

```sh
amp -x --executor runner:teeny \
  --runner-dir /var/lib/amp/code/code/github.com/samjwillis97/nix-config \
  --no-archive-after-execute -m low
```

The rendered prompt is passed on stdin, and the thread URL is parsed from Amp's
output and stored in the state database. A `continue` decision uses
`amp threads continue <url> -x <follow-up>`, so the existing thread keeps its
`teeny` executor. The dispatcher performs at most one action per run by
default, so a long investigation does not overlap the next evaluation.

Every dispatcher-created thread is labeled `triage` by default, plus
`triage-<host>` and `unit-<unit>` labels. The base label list is configurable;
labels are lowercased and normalized to Amp's alphanumeric/hyphen format. Use
`label:triage` in Amp's thread search to find all automated triage threads.

This PoC polls logs directly instead of running vmalert and Alertmanager. That
keeps the moving parts and the network surface small: the dispatcher binds no
port and only queries loopback VictoriaLogs. The alert shape is
Alertmanager-like, so vmalert can be added later without changing the gate.

`check` also updates `last_seen` and the open/resolved status. If the Amp call
fails, the dispatcher does not record the spawn; the next run can retry. The
state database defaults to `/var/lib/triage/state.db`; use `triage-state list`
to inspect it and `triage-state prune --days 30` to age it out.

## Security boundaries

- VictoriaLogs and the MCP server bind to loopback only. No firewall rule, no
  Cloudflare route, and no tailnet listener was added.
- The `probe` user has journal read access. The `amp` user has only the `probe`
  socket group. The socket is `0660 probe:probe`.
- The broker runs as `probe` with `NoNewPrivileges`, `ProtectSystem=strict`,
  `ProtectHome`, a private `/tmp`, no capabilities, and `AF_UNIX` only.
- The dispatcher runs as `triage`, not `amp`, and receives only the Amp API key
  as a systemd credential. It has no journal, probe, GitHub, or deploy access.
  It makes outbound HTTPS requests to Amp and loopback requests to
  VictoriaLogs; it binds no port. Its service sandbox uses
  `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, a private `/tmp`,
  no capabilities, and secret paths made inaccessible.
- The Amp runner's existing sandbox is unchanged: no sudo, no deploy
  credentials, and the existing inaccessible paths remain inaccessible.
- `_CMDLINE` is dropped at ingest. Log lines are still untrusted input; the
  skill says never to follow instructions found in them.
- A log line read by the agent becomes part of the Amp thread conversation and
  therefore leaves the tailnet. Keep queries narrow and redact secrets.

## Verification

```sh
nix build .#mcp-victorialogs .#teeny-probe .#triage-state .#triage-dispatcher
nix build .#checks.x86_64-linux.triage-state \
  .#checks.x86_64-linux.triage-dispatcher \
  .#checks.x86_64-linux.observability
nix build .#nixosConfigurations.teeny.config.system.build.toplevel
```

The VM test asserts that:

- `systemd-journal-upload` reaches VictoriaLogs and the test service's
  `PRIORITY:<=3` error is queryable by `_SYSTEMD_UNIT`;
- the MCP server answers an `initialize` request and identifies itself;
- the `probe` user is in `systemd-journal` and the client user is in `probe`;
- the socket is `0660` and the client can run `ping`, `journal`, `unit-status`,
  and `disk`;
- path traversal (`../../etc/passwd`) and command injection
  (`bad;rm -rf /`) are rejected;
- the dispatcher timer is active, a run invokes the fake Amp CLI with
  `runner:teeny`, and a second run inside the cooldown does not spawn again.

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
systemctl status triage-dispatcher.timer
systemctl status triage-dispatcher.service
journalctl -u victorialogs -u systemd-journal-upload -u victorialogs-mcp \
  -u triage-dispatcher --since today
```

To stop automatic spawning first, set `my.observability.triage.enable = false`
and deploy. To stop the whole PoC without losing data, also set
`my.observability.logs.enable = false` and `my.observability.probe.enable =
false`. `/var/lib/victorialogs` and `/var/lib/triage` are not deleted
automatically; decide retention separately.

## Limits and next steps

- Only `teeny` is covered. Other hosts still need a shipper and a tailnet
  listener (or a local upload) before their logs are available.
- The MCP endpoint is loopback-only, so only runner threads on `teeny` can use
  it. Exposing it to the tailnet needs an ACL or a reverse proxy with auth.
- The dispatcher polls logs directly rather than using vmalert and Alertmanager.
  That is deliberate for the PoC, but it means there is no alert grouping,
  silencing, or notification routing outside this service. vmalert can be added
  later behind the same `triage-state` gate.
- The dispatcher is single-host and performs at most one action per run. If
  more hosts produce logs later, either run one dispatcher per host or add a
  host label and a central dispatcher with per-host runner targets.
- The agent can read logs and the config repo, but it cannot run commands on
  another host. Add per-host runners or a read-only host-probe MCP only when
  that becomes necessary.
