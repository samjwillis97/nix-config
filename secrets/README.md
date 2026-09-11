# Secrets

This repository manages secrets with [SOPS](https://getsops.io/) and [sops-nix](https://github.com/Mic92/sops-nix), using native age keys.

## Key model

There are two types of age identity:

- **User/workstation identity:** belongs to one user on one workstation and normally lives at `~/.config/sops/age/keys.txt`. Home Manager uses it to decrypt user-owned secrets, and the `sops` CLI can use it to edit and rekey files.
- **System machine identity:** belongs to one NixOS machine and lives at `/var/lib/sops-nix/key.txt`. It is used by `sops-install-secrets.service` to decrypt system and service secrets during activation.

Only public `age1...` recipients belong in `.sops.yaml`. Never commit an `AGE-SECRET-KEY-...` identity.

A SOPS file is encrypted to every recipient listed in its creation rule. Any one of those recipients can decrypt it. Keep user recipients on user-owned secret groups and system recipients on service-owned groups. Include an independently backed-up editor recipient for recovery.

The NixOS module in `nixos-modules/sops.nix` generates a system machine identity when one does not already exist:

```nix
sops.age = {
  keyFile = "/var/lib/sops-nix/key.txt";
  generateKey = true;
};
```

The generated identity persists with the machine's storage. Deleting a VM disk also deletes its system identity; use an editor identity to rekey its SOPS files to the replacement machine.

## Repository layout

Each secret group has an encrypted data file and a Nix module declaring the runtime files to create:

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

Keep secret ownership aligned with its consumer. NixOS services decrypt through the system machine identity, while Home Manager decrypts user credentials through the user's workstation identity. On `wsl-personal`, Tailscale uses the system identity and `sam`'s Git identity uses the separate Home Manager identity.

## Prerequisites

Enter the development shell before running SOPS commands:

```bash
nix develop
```

The shell provides `age` and `sops`. SOPS automatically discovers the current user's identity at `~/.config/sops/age/keys.txt`.

To create a new user/workstation identity:

```bash
mkdir -p ~/.config/sops/age
chmod 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

Back up editor identities securely. A runtime-only workstation identity can instead be replaced by creating a new identity and rekeying its secret groups with an editor identity. Losing every private identity listed for a file makes that file unrecoverable.

## Adding a new machine

### 1. Bootstrap its system identity

A machine cannot activate a configuration that imports encrypted system secret groups until its private identity exists and its public recipient has been added to those groups. Create the identity explicitly on the new machine before its first secret-enabled activation. A secret-free activation is not sufficient because sops-nix only generates its age key when at least one secret is declared.

To pre-provision the identity:

```bash
age_keygen="$(nix build --no-link --print-out-paths nixpkgs#age)/bin/age-keygen"
sudo install -d -m 0700 /var/lib/sops-nix
sudo "$age_keygen" -o /var/lib/sops-nix/key.txt
sudo chmod 0600 /var/lib/sops-nix/key.txt
sudo "$age_keygen" -y /var/lib/sops-nix/key.txt
```

The final command prints only the public `age1...` system recipient. Keep the private identity on the machine; do not copy it into the repository or reuse another machine's identity.

### 2. Bootstrap its Home Manager user identity

For a workstation user with Home Manager secrets, create a second identity as that user:

```bash
age_keygen="$(nix build --no-link --print-out-paths nixpkgs#age)/bin/age-keygen"
install -d -m 0700 ~/.config/sops/age
"$age_keygen" -o ~/.config/sops/age/keys.txt
chmod 0600 ~/.config/sops/age/keys.txt
"$age_keygen" -y ~/.config/sops/age/keys.txt
```

The final command prints the public user recipient. Keep this key distinct from `/var/lib/sops-nix/key.txt`; do not copy an existing editor or workstation identity into the new user's home.

### 3. Register the public recipients

Add separate anchors under `keys` in `.sops.yaml`:

```yaml
keys:
  - &desktop age1EDITOR_RECIPIENT
  - &new-machine-system age1NEW_SYSTEM_RECIPIENT
  - &new-machine-user age1NEW_USER_RECIPIENT
```

Add the system anchor only to service-owned groups:

```yaml
creation_rules:
  - path_regex: ^secrets/tailscale/secrets\.yaml$
    key_groups:
      - age:
          - *desktop
          - *new-machine-system
```

Add the user anchor only to Home Manager groups:

```yaml
  - path_regex: ^secrets/development/secrets\.yaml$
    key_groups:
      - age:
          - *desktop
          - *new-machine-user
```

Keep alternative recipients under the same `age` entry. Multiple separate age key groups introduce threshold semantics rather than alternative recipients.

### 4. Rekey existing files

Changing `.sops.yaml` does not modify existing encrypted files. Update each affected file:

```bash
sops updatekeys --yes secrets/tailscale/secrets.yaml
```

The `wsl-personal` host consumes both groups through different identities: add its system recipient only to the Tailscale rule and `sam`'s user recipient only to the development rule. Rekey both before the first activation:

```bash
sops updatekeys --yes secrets/tailscale/secrets.yaml
sops updatekeys --yes secrets/development/secrets.yaml
```

The command must be run while an identity that can decrypt the current file is still available. Do not remove or destroy the old identity before rekeying and verifying.

### 5. Import the group and rebuild

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
sudo test -r /run/secrets/<system-secret-name>
test -r ~/.config/sops-nix/secrets/<home-secret-name>
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
