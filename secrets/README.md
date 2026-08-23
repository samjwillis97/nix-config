# Secrets

This repository manages secrets with [SOPS](https://getsops.io/) and [sops-nix](https://github.com/Mic92/sops-nix), using native age keys.

## Key model

There are two types of age identity:

- **Editor identity:** belongs to a person or workstation and normally lives at `~/.config/sops/age/keys.txt`. It is used by the `sops` CLI to create, edit, and rekey files.
- **Machine identity:** belongs to one NixOS machine and lives at `/var/lib/sops-nix/key.txt`. It is used by `sops-install-secrets.service` during activation.

Only public `age1...` recipients belong in `.sops.yaml`. Never commit an `AGE-SECRET-KEY-...` identity.

A SOPS file is encrypted to every recipient listed in its creation rule. Any one of those recipients can decrypt it. Normally each rule contains at least one editor recipient for recovery and the machine recipients that need that secret group.

The NixOS module in `nixos-modules/sops.nix` generates a machine identity when one does not already exist:

```nix
sops.age = {
  keyFile = "/var/lib/sops-nix/key.txt";
  generateKey = true;
};
```

The generated identity persists with the machine's storage. Deleting a VM disk also deletes its machine identity; use an editor identity to rekey its SOPS files to the replacement machine.

## Repository layout

Each secret group has an encrypted data file and a NixOS module declaring the runtime files to create:

```text
.sops.yaml
secrets/
  README.md
  tailscale/
    default.nix
    secrets.yaml
```

`flake-module.nix` discovers directories under `secrets/` and exposes them through `secretModules`. A host imports only the groups it needs:

```nix
{ secretModules, ... }:
{
  imports = [ secretModules.tailscale ];
}
```

Decrypted values are written to `/run/secrets` by default. Consumers must use the generated path rather than reading secret data during Nix evaluation:

```nix
config.sops.secrets."tailscale-auth-key".path
```

## Prerequisites

Enter the development shell before running SOPS commands:

```bash
nix develop
```

The shell provides `age` and `sops`. SOPS automatically discovers the editor identity at `~/.config/sops/age/keys.txt`.

To create a new editor identity:

```bash
mkdir -p ~/.config/sops/age
chmod 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

Back up the private editor identity securely. Losing every private identity listed for a file makes that file unrecoverable.

## Adding a new machine

### 1. Bootstrap its machine identity

Ensure the machine imports `nixos-modules/sops.nix`, but do not yet import secret groups it cannot decrypt. Build and boot it once. During activation, sops-nix creates:

```text
/var/lib/sops-nix/key.txt
```

Obtain its public recipient on the machine:

```bash
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

This prints only the public `age1...` recipient.

### 2. Register the public recipient

Add an anchor under `keys` in `.sops.yaml`:

```yaml
keys:
  - &desktop age1EDITOR_RECIPIENT
  - &new-machine age1NEW_MACHINE_RECIPIENT
```

Add that anchor only to creation rules for groups the machine needs:

```yaml
creation_rules:
  - path_regex: ^secrets/tailscale/secrets\.yaml$
    key_groups:
      - age:
          - *desktop
          - *new-machine
```

Keep alternative recipients under the same `age` entry. Multiple separate age key groups introduce threshold semantics rather than alternative recipients.

### 3. Rekey existing files

Changing `.sops.yaml` does not modify existing encrypted files. Update each affected file:

```bash
sops updatekeys --yes secrets/tailscale/secrets.yaml
```

The command must be run while an identity that can decrypt the current file is still available. Do not remove or destroy the old identity before rekeying and verifying.

### 4. Import the group and rebuild

Add the group to the machine's imports:

```nix
{ secretModules, ... }:
{
  imports = [ secretModules.tailscale ];
}
```

Build the configuration:

```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel
```

For a QEMU VM configuration, build its launcher with:

```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.vm
```

After activation, verify without printing secret contents:

```bash
sudo systemctl status sops-install-secrets.service
sudo test -r /run/secrets/<secret-name>
```

## Creating a new secret in an existing group

For example, to add another value to the `tailscale` group:

### 1. Edit the encrypted file

```bash
sops edit secrets/tailscale/secrets.yaml
```

Add the new YAML key in the decrypted editor buffer:

```yaml
tailscale-auth-key: existing-value
new-secret: new-value
```

Saving and closing the editor re-encrypts the file. Never create or commit a plaintext copy.

### 2. Declare its runtime file

Add the key to the group's `default.nix`:

```nix
{
  sops.secrets = {
    "tailscale-auth-key" = {
      sopsFile = ./secrets.yaml;
    };

    "new-secret" = {
      sopsFile = ./secrets.yaml;
    };
  };
}
```

By default, the secret is written as `/run/secrets/new-secret` with restrictive root ownership. Set `owner`, `group`, or `mode` only when the consuming service requires different access:

```nix
"new-secret" = {
  sopsFile = ./secrets.yaml;
  owner = "service-user";
  group = "service-group";
  mode = "0440";
};
```

### 3. Pass the path to its consumer

```nix
services.example.credentialsFile = config.sops.secrets."new-secret".path;
```

Prefer options ending in `File`, `Path`, or `CredentialsFile`. Do not use `builtins.readFile` on a runtime secret; doing so either fails during evaluation or risks placing plaintext in the Nix store.

### 4. Rebuild and verify

Rebuild each machine consuming the group, then check that the runtime file exists without printing it:

```bash
sudo test -r /run/secrets/new-secret
```

## Creating a new secret group

A secret group defines an access boundary. Create a separate group when its files need different machine recipients or are imported by different hosts.

For a group named `example`:

### 1. Add its creation rule

Add a path-specific rule to `.sops.yaml` before creating the encrypted file:

```yaml
creation_rules:
  - path_regex: ^secrets/example/secrets\.yaml$
    key_groups:
      - age:
          - *desktop
          - *new-machine
```

Specific rules should appear before any broader fallback rule.

### 2. Create the encrypted file

```bash
mkdir -p secrets/example
sops edit secrets/example/secrets.yaml
```

Enter the initial values in the editor and save. Confirm the file contains `ENC[...]` values and a `sops:` metadata section before adding it to Git.

### 3. Declare the group

Create `secrets/example/default.nix`:

```nix
{
  sops.secrets."example-api-key" = {
    sopsFile = ./secrets.yaml;
  };
}
```

The SOPS secret name defaults to the YAML key. If the runtime name and YAML key differ, set `key` explicitly:

```nix
sops.secrets."service-api-key" = {
  sopsFile = ./secrets.yaml;
  key = "example-api-key";
};
```

### 4. Import it on the intended machines

```nix
{ secretModules, ... }:
{
  imports = [ secretModules.example ];
}
```

Rebuild and verify the resulting `/run/secrets/...` files.

## Rekeying secrets

Rekey whenever recipients are added, removed, or replaced in `.sops.yaml`.

### Update one group

```bash
sops updatekeys --yes secrets/tailscale/secrets.yaml
```

### Update every group

```bash
for file in secrets/*/secrets.yaml; do
  sops updatekeys --yes "$file"
done
```

`updatekeys` synchronizes the recipients embedded in each file with the first matching creation rule in `.sops.yaml`.

Verify that an intended identity can decrypt without displaying the values:

```bash
sops decrypt secrets/tailscale/secrets.yaml >/dev/null
```

When revoking a compromised identity, also rotate the file's data key after removing the recipient and running `updatekeys`:

```bash
sops rotate --in-place secrets/tailscale/secrets.yaml
```

Rotation protects the current version from a party that retained the previous data key. It cannot revoke access to plaintext or encrypted history that the party already obtained.

## Editing secrets

Open a file through SOPS:

```bash
nix develop
sops edit secrets/tailscale/secrets.yaml
```

SOPS decrypts into a temporary editor buffer and encrypts the file again when the editor exits successfully. It uses `$SOPS_EDITOR`, then `$EDITOR`, and otherwise its configured default editor.

Useful non-plaintext checks:

```bash
sops filestatus secrets/tailscale/secrets.yaml
sops decrypt secrets/tailscale/secrets.yaml >/dev/null
```

After editing a value, rebuild or reactivate every consuming machine. If a service must react immediately to changes, declare it on the secret:

```nix
sops.secrets."example-api-key" = {
  sopsFile = ./secrets.yaml;
  restartUnits = [ "example.service" ];
};
```

Then verify both secret installation and the consuming service:

```bash
sudo systemctl status sops-install-secrets.service
sudo systemctl status example.service
```

## Security rules

- Commit `.sops.yaml`, encrypted `secrets.yaml` files, and Nix declarations.
- Never commit native age private identities or plaintext secret files.
- Keep editor identities at mode `0600` and back them up securely.
- Give each machine a distinct identity; do not copy an editor identity into a machine.
- Include only the machines that require each secret group.
- Rekey files before destroying an old identity.
- Never print secret values during routine verification.
- Treat old Git revisions as still accessible to recipients that could decrypt them at the time.
