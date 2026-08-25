# Terranix

This directory contains Terranix modules that render OpenTofu configuration for infrastructure managed by the flake.

Register each configuration under `terranix.terranixConfigurations` in `flake.nix`. Pass shared values through `extraArgs`, assign a separate working directory, and keep provider, resource, data-source, and output definitions in the corresponding module.

Enter a configuration's generated development shell before running OpenTofu:

```console
nix develop .#<name>
tofu plan
tofu apply
```

Inject credentials at runtime through the Terraform wrapper and SOPS; never place plaintext credentials in Nix source or interpolate them into the Nix store.
