# Flake templates

Templates are reusable starter flakes exposed through this repository's
`templates` output. The discovery rule is implemented in `flake-module.nix`:
the normal shape is a directory beneath `templates/` containing a `flake.nix`
entry point. The directory name becomes the template name, and no second
registration list is required. The generic scanner also recognizes a regular
`.nix` file directly under `templates/`; use the directory shape when the
template needs supporting files or its own lock file.

## Discover available templates

Query the flake instead of copying a template inventory into documentation:

```sh
nix eval --json .#templates --apply builtins.attrNames |
  jq -r '.[]'
```

To inspect exported template metadata (including each description and source
path), evaluate the output attrset as JSON:

```sh
nix eval --json .#templates
```

The exported template path is the directory containing the discovered
`flake.nix`, so supporting files such as `.envrc` and `flake.lock` are copied
with the template.

## Initialize a destination

Set the source flake before changing directories, then create a destination
from the discovered template:

```sh
template_source="$(pwd)"
template_name=node
destination="$PWD/my-node-project"
nix flake new --template "$template_source#${template_name}" "$destination"
cd "$destination"
nix flake show
```

`nix flake init --template "$template_source#${template_name}"` is the
equivalent when the current directory is already the intended destination.
Capture `template_source` first; after `cd`, a relative `.#name` refers to the
destination rather than this repository. Do not initialize into a directory
containing files you need to preserve unless the Nix command's merge behavior
is understood; use a new destination or make a backup first.

After initialization, enter the generated development shell when the project
needs its tools:

```sh
nix develop
```

If direnv is installed, the copied `.envrc` contains `use flake .`, so allowing
that file will activate the same shell automatically. Direnv does not install
project dependencies or execute a language package manager for you.

## The Node template

`templates/node/` is deliberately a small Nix development scaffold, not a
complete Node application. Its `flake.nix` currently:

- declares its own Nix tooling inputs and imports the git-hooks flake module;
  enables the hook set defined in that file;
- advertises an explicit `systems` list (inspect the file or `nix flake show`
  rather than assuming every host platform is supported);
- adds the enabled hook packages and `nodejs` to `devShells.default`;
- appends `$PWD/node_modules/.bin` to `PATH` in the shell hook, so existing
  executables earlier on `PATH` take precedence over project-local binaries.

The exact hook/tool set is source-controlled in `templates/node/flake.nix`;
inspect that file when updating the template instead of copying a
drift-prone inventory into this guide.

The template contains no `package.json`, source tree, lockfile for a Node
package manager, or dependency installation step. After creating a project,
add the Node project files and install dependencies using the package manager
and policy chosen by that project. The `node_modules/.bin` path is useful once
those dependencies exist; it is not a replacement for installing them.

The generated `flake.lock` pins the template's Nix inputs at initialization
time. When changing the template's input declarations, update its lock file
intentionally and review the resulting diff. Do not copy a lock file from an
unrelated project.

## Add or update a template

To update the Node scaffold, edit `templates/node/flake.nix` for development
shell or hook behavior and `.envrc` for direnv activation. Keep the template
self-contained: paths should work after the directory is copied away from this
repository.

To add another template:

1. Create `templates/name/` with a valid `flake.nix` at its root.
2. Add any files that should be initialized alongside the flake (for example,
   an environment activation file or project configuration).
3. Confirm discovery and evaluate the copied result:

   ```sh
   template_source="$(pwd)"
   template_name=name
   destination="$PWD/template-smoke"
   nix eval --json "$template_source#templates" --apply builtins.attrNames |
     jq -e --arg name "$template_name" 'any(.[]; . == $name)'
   nix flake new --template "$template_source#${template_name}" "$destination"
   nix flake show "$destination"
   nix flake check "$destination"
   ```

   Use a temporary destination that is safe to remove after inspection. Do
   not add the destination to this repository merely to make discovery work.

For the Node template specifically, also verify that its development shell
provides Node:

```sh
nix develop "$destination" --command sh -c 'command -v node'
```

The discovery code does not inspect arbitrary files beneath a template or
infer a template from a README. A missing or misnamed root `flake.nix` means
that the directory is not exported. A template's own `systems` list controls
where its development shell can be evaluated; update it when adding platform
support and make sure every enabled hook/tool is available there.
