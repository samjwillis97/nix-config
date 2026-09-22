# Secrets

This repository stores encrypted values with [SOPS](https://getsops.io/) and [sops-nix](https://github.com/Mic92/sops-nix), using native [age](https://age-encryption.org/) recipients. The repository contains ciphertext and public recipients; decryption happens only with a private age identity on the editor, target machine, or Home Manager account that needs the value.

Read this guide together with the [NixOS module guide](../nixos-modules/README.md), [Darwin module guide](../darwin-modules/README.md), [host guide](../nixos-hosts/README.md), [user guide](../users/README.md), and [Terranix guide](../terranix/README.md). Deployment-specific commands belong in [operations](../docs/operations.md).

## The two halves of a secret

There are two separate pieces to every secret:

1. **Encrypted data** lives in a SOPS YAML file. Its `sops.age` metadata contains one encrypted data key for each configured recipient. The YAML values remain ciphertext in Git.
2. **A runtime declaration** in a `secrets/*/default.nix` file tells sops-nix which YAML key to install and gives consumers a generated path. A declaration does not grant access by itself; the private identity used at runtime must correspond to a recipient in the encrypted file.

The source of truth for future encryption and recipient changes is `.sops.yaml`. Its creation rules are path-specific. Changing `.sops.yaml` does **not** rewrite an existing encrypted file; run `sops updatekeys` for each affected file.

## Age identities and recipient scope

An age **recipient** is public. It starts with `age1...`, may be committed in `.sops.yaml`, and is also recorded in encrypted file metadata. An age **identity** is private. It starts with `AGE-SECRET-KEY-...` and must stay on the machine or account that uses it. Never put a private identity in Git, Nix source, a Nix store path, an issue, or a command/output log.

Use separate identities for separate trust boundaries:

- A **CLI/editor identity** is available to the person who edits or rekeys files. Keep at least one independently backed-up editor/recovery identity that is not tied to one machine's lifetime.
- A **system identity** belongs to one NixOS or Darwin installation. Do not copy it to another machine. The system modules in this repository configure it at `/var/lib/sops-nix/key.txt` and set `generateKey = true`.
- A **Home Manager identity** belongs to one user on one workstation. The Home Manager module configures it at `${config.home.homeDirectory}/.config/sops/age/keys.txt`, normally `~/.config/sops/age/keys.txt`.

A recipient in a rule is an access grant, not a label. Add a runtime recipient only to groups the corresponding runtime actually needs. If one encrypted file is consumed by both a system service and Home Manager, its single `age` list must contain both the required system and user recipients, as well as an editor/recovery recipient where appropriate. Do not add every machine or user to every group for convenience.

### Where this repository loads private identities

| Consumer                                  | Configured private-key location and loader                                                                                                                                                                                          |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SOPS CLI in the default development shell | `flake.nix` exports `SOPS_AGE_KEY_FILE` as `$HOME/.config/sops/age/keys.txt`; `sops` then uses that user identity.                                                                                                                  |
| NixOS system secrets                      | `nixos-modules/sops.nix` configures `/var/lib/sops-nix/key.txt`, enables systemd activation, and installs `age`. sops-nix uses this identity while installing declared system secrets.                                              |
| Darwin system secrets                     | `darwin-modules/sops.nix` configures the same `/var/lib/sops-nix/key.txt` location, enables key generation, and installs `age`. Darwin activation is not a systemd activation, so do not use the NixOS `systemctl` check on Darwin. |
| Home Manager secrets                      | `home-modules/sops.nix` points sops-nix at the Home Manager user's `~/.config/sops/age/keys.txt`. The Home Manager module is included for both NixOS and Darwin configurations by `flake-module.nix`.                               |

The NixOS and Darwin modules can generate the system identity when a secret-enabled activation needs it. If a recipient must be added to an encrypted file before the first activation, pre-provision the system key as described below. A generated key is stored with the installation; losing that storage loses that runtime identity.

## Prerequisites and safe identity checks

Enter the repository development shell before using SOPS commands. It supplies `age`, `ssh-to-age`, and `sops` and sets the CLI identity path:

```bash
nix develop
command -v age-keygen sops
editor_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -r "$editor_key_file"
```

To create a new editor/Home Manager identity, choose a path that does not already contain a key. The final command prints only the public recipient:

```bash
key_file="$HOME/.config/sops/age/keys.txt"
test ! -e "$key_file" || { printf '%s\n' 'Key already exists; do not overwrite it.' >&2; exit 1; }
install -d -m 0700 "$(dirname "$key_file")"
umask 077
age-keygen -o "$key_file"
chmod 0600 "$key_file"
age-keygen -y "$key_file"
```

Back up the private identity securely before relying on it as an editor or recovery key. Keep the backup protected separately from the repository. `age-keygen -y` is the safe way to derive the public recipient for `.sops.yaml`; never copy the contents of the private file into the configuration.

To pre-provision a system identity before a secret-enabled activation, run this on the target installation. The guard prevents replacing an existing key:

```bash
system_key_file="/var/lib/sops-nix/key.txt"
age_keygen="$(nix build --no-link --print-out-paths nixpkgs#age)/bin/age-keygen"
if sudo test -e "$system_key_file"; then
  printf '%s\n' 'System age identity already exists; keep it and use its public recipient.' >&2
  exit 1
fi
sudo install -d -m 0700 "$(dirname "$system_key_file")"
sudo "$age_keygen" -o "$system_key_file"
sudo chmod 0600 "$system_key_file"
sudo "$age_keygen" -y "$system_key_file"
```

The last command prints only the target's public recipient. Keep the private system identity on that target and do not reuse an editor, Home Manager, or other machine identity. If the configured module is allowed to generate the key during activation, pre-provisioning is optional; it is useful when the recipient must be registered before that activation can decrypt anything.

## Repository layout and current rule structure

`flake-module.nix` builds `secretModules` with `readModules { dir = ./secrets; }`: a direct `.nix` file or a subdirectory containing `default.nix` becomes a module attribute. A data-only directory (such as a directory containing Terranix ciphertext but no `default.nix`) is not a `secretModules` entry. There is no second registry to update. A group normally contains an encrypted YAML file and a Nix declaration:

```text
secrets/
  example/
    default.nix
    secrets.yaml
```

NixOS host modules receive `secretModules` through the `nixosConfigurations` special arguments, and Home Manager user modules receive it through the Home Manager integration:

```nix
{ secretModules, ... }:
{
  imports = [ secretModules.example ];
}
```

The current Darwin host special arguments do not include `secretModules`; the existing Darwin host modules therefore do not use this direct-import example. If a Darwin system needs a system-level secret group, wire that argument through the Darwin module assembly before importing a group. Home Manager user modules remain the user-side route where they are enabled.

The current `.sops.yaml` uses path-specific rules: exact paths for fixed group data and basename-scoped regular expressions for machine-specific YAML files beneath `secrets/`. It intentionally has no catch-all rule. Do not treat this guide's examples as an inventory; inspect `.sops.yaml` before creating or renaming a file. A new path needs a matching rule, and a broad rule must not accidentally grant access to an unrelated group. The machine-specific rules follow the `^secrets/(.*/)?<basename>[.]yaml$` shape, with each basename explicitly configured; preserve the repository's existing regex syntax and recipient scope rather than assuming every new filename is covered.

Each current rule has one `key_groups` entry containing one `age` list. Recipients in that one list are alternatives: any one corresponding private identity can decrypt the data key. Do not split alternative recipients into separate `key_groups`; separate groups introduce SOPS threshold/group semantics instead of simply adding another allowed recipient. Keep specific rules before broader rules because SOPS uses the first matching creation rule.

The encrypted file's `sops.age[].recipient` metadata is the effective recipient set for that committed ciphertext. Compare it with the intended rule after recipient changes, but do not decrypt values as part of the comparison. `.sops.yaml` controls future `sops edit`/`sops encrypt` operations and `updatekeys`; it is not a retroactive ACL until existing files are updated.

## Adding recipients

A recipient change has three parts: generate or obtain the private identity on the intended target/account, register only its public recipient in `.sops.yaml`, and synchronize each affected encrypted file. Do not remove the old identity until the new one has been tested.

### Add a system recipient for a machine

1. Generate or pre-provision the target's `/var/lib/sops-nix/key.txt` and record only the public output from `age-keygen -y`.
2. Add a descriptive public-recipient anchor under `keys` in `.sops.yaml`:

   ```yaml
   keys:
     - &new-system age1PUBLIC_RECIPIENT_FROM_THE_TARGET
   ```

3. Add `*new-system` only to the `age` list of each path rule whose system service runs on that target. For a host-specific file, ensure the target's `config.networking.hostName` produces a filename matched by a creation rule. Do not add a system recipient to Home Manager-only data unless the system genuinely needs it.
4. For every existing encrypted file affected by the rule, run `sops updatekeys --yes`. A new encrypted file receives the rule when it is first created, but a renamed or already committed file still needs an explicit update.
5. Activate the target configuration. The private key remains on the target; a build machine only needs the encrypted source and public metadata.

### Add a Home Manager user recipient

1. As the intended user, create or locate that user's `~/.config/sops/age/keys.txt` and derive its public recipient with `age-keygen -y`.
2. Add a descriptive public anchor to `.sops.yaml` and add that anchor only to user-owned groups. The existing `development` declaration is imported by user modules and is a model for this pattern; do not infer access from the module name alone.
3. If the user and a system service consume the same encrypted file, add both recipients explicitly and rekey the file. A Home Manager import does not make the system identity usable, and a system import does not make the user identity usable.
4. Run `sops updatekeys --yes` for every affected existing file while the current editor identity can still decrypt it. Activate Home Manager through the target's NixOS/Darwin configuration and verify only file existence/readability.

### Add an editor or recovery recipient

Create a separately backed-up editor identity, add only its public recipient to the groups it must recover, and run `sops updatekeys --yes` on those existing files. Keeping a recovery recipient on every group prevents the loss of one machine disk from making that group's ciphertext unrecoverable. It does not grant a runtime service access unless that service also has the corresponding private identity.

## Creating and declaring secrets

### Add a value to an existing group

Use `sops edit` so the plaintext exists only in SOPS's temporary editor buffer:

```bash
secret_group="replace-with-group-name"
secret_file="secrets/${secret_group}/secrets.yaml"
sops edit "$secret_file"
```

Add the YAML key in the editor and save/exit successfully. Do not create a plaintext copy, shell variable, command-line argument, editor swap file, or backup file containing the value. Declare the same key in that group's `default.nix`:

```nix
{
  sops.secrets = {
    "existing-secret" = {
      sopsFile = ./secrets.yaml;
    };

    "new-secret" = {
      sopsFile = ./secrets.yaml;
    };
  };
}
```

Nested YAML keys use slash names in sops-nix declarations, as in `"service/api-key"`. If the runtime name should differ from the YAML key, set `key` explicitly:

```nix
sops.secrets."service-api-key" = {
  sopsFile = ./secrets.yaml;
  key = "service/api-key";
};
```

The declaration's `sopsFile` must point to the encrypted file containing the key. A module that serves host-specific files can select the file dynamically, for example:

```nix
sops.secrets."host-token" = {
  sopsFile = ./. + "/${config.networking.hostName}.yaml";
};
```

That pattern requires one encrypted file per target name and a matching `.sops.yaml` creation rule for each file path or filename pattern. Do not add a file and assume that the dynamic Nix expression also grants its recipients.

### Create a new group

Use a group when its data needs a different recipient boundary or is consumed by a different set of systems. Add a path-specific rule **before** creating the file:

```yaml
creation_rules:
  - path_regex: ^secrets/example/secrets[.]yaml$
    key_groups:
      - age:
          - *editor
          - *required-runtime
```

Use anchors that already exist in `.sops.yaml` or add their public values under `keys`. Keep only recipients that need this group's data. Then create the encrypted file through SOPS:

```bash
secret_group="example"
secret_file="secrets/${secret_group}/secrets.yaml"
mkdir -p "$(dirname "$secret_file")"
sops edit "$secret_file"
sops filestatus "$secret_file"
```

The saved file should contain SOPS-encrypted values and a `sops` metadata section. `sops filestatus` is a non-plaintext status check. If an existing controlled plaintext input must be encrypted instead, `sops encrypt` applies the matching creation rule; treat the input as sensitive, never log or commit it, and remove the temporary plaintext only after confirming the encrypted output:

```bash
secret_group="example"
secret_file="secrets/${secret_group}/secrets.yaml"
plain_file="replace-with-private-temporary-yaml"
sops encrypt --input-type yaml --output "$secret_file" "$plain_file"
```

Do not use `sops encrypt` with a tracked or casually saved plaintext file. `sops edit` is preferred for normal creation and changes because it manages the temporary editor buffer.

### Connect the declaration to a consumer

Import the group in each intended host or user module:

```nix
{ secretModules, ... }:
{
  imports = [ secretModules.example ];
}
```

Pass the generated path to the consuming option rather than reading the value during evaluation:

```nix
services.example.credentialsFile = config.sops.secrets."new-secret".path;
```

Current consumers follow this pattern: system modules pass generated paths to service options such as `authKeyFile`, `tokenFile`, `apiKeyFile`, `adminPasswordFile`, or other `*File` settings, while Home Manager's Git configuration passes its generated path as a key file. Keep the path reference in Nix and let the service read the runtime file.

Prefer consumer options ending in `File`, `Path`, or `CredentialsFile`. Where a module needs a generated unit/configuration placeholder, use `config.sops.placeholder.<name>` as the module's existing pattern does. Never use `builtins.readFile` on a runtime secret: that either fails during evaluation or places plaintext in the Nix store.

System secret files default to the system runtime secret directory and root ownership with restrictive permissions. Set `owner`, `group`, or `mode` only when the service genuinely needs different access:

```nix
"new-secret" = {
  sopsFile = ./secrets.yaml;
  owner = "service-user";
  group = "service-group";
  mode = "0440";
};
```

Home Manager secrets are installed for the Home Manager user under its sops-nix user-side path. In all cases, use `config.sops.secrets."name".path` instead of constructing a path by hand.

## Editing, rekeying, and rotating

These commands solve different problems:

| Command                       | Changes                                                                                                                                    | Use it for                                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `sops edit FILE`              | Opens a temporary decrypted editor buffer and writes encrypted output on successful exit.                                                  | Adding/changing values in a group, including normal new-file creation.                             |
| `sops encrypt ...`            | Encrypts a supplied plaintext input using the creation rule matching the output path.                                                      | Controlled one-time imports where a plaintext input already exists; protect and delete that input. |
| `sops updatekeys --yes FILE`  | Synchronizes the file's encrypted data-key recipients with the first matching `.sops.yaml` creation rule. It does not rotate the data key. | Adding/removing/replacing recipients after changing `.sops.yaml`.                                  |
| `sops rotate --in-place FILE` | Generates a new data key and re-encrypts the file.                                                                                         | Reducing exposure after a recipient compromise, after updating recipients.                         |

For one file:

```bash
secret_group="replace-with-group-name"
secret_file="secrets/${secret_group}/secrets.yaml"
sops updatekeys --yes "$secret_file"
```

For all tracked encrypted YAML files, including host-specific and Terranix files, use the repository file list rather than a shallow directory glob:

```bash
git ls-files 'secrets/**/*.yaml' | while IFS= read -r secret_file; do
  sops updatekeys --yes "$secret_file"
done
```

Run these commands only while an identity that can still decrypt each current file is available. If a path has no matching creation rule, stop and add the intended specific rule before retrying; do not invent a broad rule just to make the command pass.

When an identity is compromised, remove its public recipient from `.sops.yaml`, run `updatekeys` on every affected file, then rotate each affected file's data key:

```bash
secret_group="replace-with-group-name"
secret_file="secrets/${secret_group}/secrets.yaml"
sops updatekeys --yes "$secret_file"
sops rotate --in-place "$secret_file"
```

Rotation protects the current ciphertext from someone who retained the previous data key. It cannot revoke plaintext already obtained, erase old Git revisions, or make a leaked credential safe; rotate the underlying credential as well. Removing a recipient from the current file does not remove that recipient's ability to read historical encrypted revisions.

For non-plaintext checks after an edit or rekey:

```bash
secret_group="replace-with-group-name"
secret_file="secrets/${secret_group}/secrets.yaml"
sops filestatus "$secret_file"
sops decrypt "$secret_file" >/dev/null
```

The second command tests decryption with the selected private identity and discards plaintext. Never omit the redirect in routine checks, print the value, or run a shell with tracing enabled around secret commands.

## Activation, ownership, and deployment

A build evaluates declarations; it does not make a private identity available to the target. At activation time:

- NixOS system secrets are installed by sops-nix using `/var/lib/sops-nix/key.txt`; this repository enables systemd activation, so `sops-install-secrets.service` is the relevant NixOS status check.
- Darwin system secrets use the same configured system key path during Darwin activation. Check the activation result and the generated file; do not assume a NixOS systemd service exists.
- Home Manager secrets require the Home Manager user's private key at `~/.config/sops/age/keys.txt`. In this repository Home Manager is integrated into NixOS and Darwin configurations, so activate the owning host/user configuration.

Build a target with a user-supplied configuration name:

```bash
nixos_name="replace-with-nixos-configuration-name"
nix build ".#nixosConfigurations.${nixos_name}.config.system.build.toplevel"
```

For Darwin, use the corresponding configuration output and activation workflow:

```bash
darwin_name="replace-with-darwin-configuration-name"
nix build ".#darwinConfigurations.${darwin_name}.system"
```

Remote deployment must leave the target's private system identity on the target. Do not copy it into a build host, CI artifact, Nix expression, or deployment argument. See [operations](../docs/operations.md) for the repository's deployment workflow.

Verify installation without reading a secret. Substitute the declaration name in shell variables rather than placing secret contents in a command:

```bash
system_secret_name="replace-with-system-secret-name"
system_secret_path="/run/secrets/${system_secret_name}"
sudo test -r "$system_secret_path"

home_secret_name="replace-with-home-secret-name"
home_secret_path="$HOME/.config/sops-nix/secrets/${home_secret_name}"
test -r "$home_secret_path"
```

On NixOS only, also inspect the installation unit without displaying values:

```bash
sudo systemctl status sops-install-secrets.service
```

If a service must react immediately when a secret changes, declare its unit in the secret declaration:

```nix
sops.secrets."new-secret" = {
  sopsFile = ./secrets.yaml;
  restartUnits = [ "example.service" ];
};
```

Check the consuming service's status after activation. A missing recipient, missing private key, wrong `sopsFile`, or wrong ownership should be fixed in the declaration/recipient workflow; do not work around it by copying a private key or loosening permissions globally.

## Terranix integration

`secrets/terranix/cloudflare.yaml` is a Terranix input, not a `secretModules` declaration. The corresponding Terranix wrapper in `flake.nix` runs SOPS at runtime, extracts only the configured API-token field, and exports it for the OpenTofu process. It does not put the token in Nix source or the Nix store.

Use the generated Terranix shell and the workflow in [`terranix/README.md`](../terranix/README.md):

```bash
terranix_name="replace-with-terranix-configuration-name"
nix develop ".#${terranix_name}"
tofu plan
tofu apply
```

The current `.sops.yaml` has an exact creation rule for the Terranix ciphertext. If its recipient set changes, update that rule and run `sops updatekeys --yes secrets/terranix/cloudflare.yaml` while an existing editor identity is still available. Never print the exported token or add it to a Terraform variable file.

## Recovery and security rules

- Commit `.sops.yaml`, encrypted YAML files, and Nix declarations; never commit age private identities, plaintext YAML, editor swap files, or decrypted backups.
- Keep private key files mode `0600` and parent directories private. Protect offline backups as carefully as the live identity.
- Use distinct system identities for distinct installations and distinct Home Manager identities for distinct users/workstations. Never copy one machine's `/var/lib/sops-nix/key.txt` to another machine.
- Register only public recipients. `age-keygen -y` is sufficient to derive one; do not expose the private file to obtain it.
- A recipient added only to `.sops.yaml` cannot decrypt old files until `sops updatekeys` updates those files. Conversely, removing it from `.sops.yaml` does not rewrite old Git history.
- Before destroying, reprovisioning, or revoking an identity, rekey all affected current files and verify decryption with the replacement identity. For compromise, rotate the SOPS data key and the underlying credential.
- If no private identity can decrypt a ciphertext, the ciphertext alone is not recoverable. Restore a protected editor/recovery identity; never paste a private key into chat, an issue, a repository, or a build log.
- Treat old Git revisions as accessible to any recipient that could decrypt them at the time. History cleanup is destructive and does not replace credential rotation.
- Routine checks must prove status, decryption exit code, file readability, and service activation without printing secret values. Avoid shell tracing and commands that place plaintext in process arguments or logs.
