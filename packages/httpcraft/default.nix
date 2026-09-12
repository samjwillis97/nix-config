{
  lib,
  stdenv,
  buildNpmPackage,
  nodejs_22,
  pkg-config,
  libsecret,
  runCommand,
  python3,
}:
let
  httpcraft = buildNpmPackage (finalAttrs: {
    pname = "httpcraft";
    version = "1.0.0";

    nodejs = nodejs_22;
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./src
        ./schemas
        ./examples
        ./package.json
        ./package-lock.json
        ./tsconfig.json
        ./README.md
      ];
    };

    npmDepsHash = "sha256-h9Tyh0HAzLvn20mGIYHmKFyu/0nHWRa83XqC6HWd2+0=";
    npmBuildScript = "build";
    npmPackFlags = [ "--ignore-scripts" ];
    npmDepsFetcherVersion = 1;
    env.npm_config_build_from_source = "true";
    # keytar 7.9.0's node-addon-api 4.3.0 uses an out-of-range enum sentinel
    # rejected by current Clang. Skip the generic rebuild, patch that dependency,
    # then rebuild keytar explicitly before the normal TypeScript build.
    npmRebuildFlags = [ "--ignore-scripts" ];
    preBuild = ''
      substituteInPlace node_modules/node-addon-api/napi.h \
        --replace-fail \
          '    static const napi_typedarray_type unknown_array_type = static_cast<napi_typedarray_type>(-1);' \
          '    static const int unknown_array_type = -1;'
      substituteInPlace node_modules/node-addon-api/napi.h \
        --replace-fail \
          '        : unknown_array_type;' \
          '        : static_cast<napi_typedarray_type>(unknown_array_type);'
      substituteInPlace node_modules/node-addon-api/napi-inl.h \
        --replace-fail \
          '_type(TypedArray::unknown_array_type)' \
          '_type(static_cast<napi_typedarray_type>(TypedArray::unknown_array_type))'
      substituteInPlace node_modules/node-addon-api/napi-inl.h \
        --replace-fail \
          'if (_type == TypedArray::unknown_array_type)' \
          'if (_type == static_cast<napi_typedarray_type>(TypedArray::unknown_array_type))'
      npm rebuild --offline keytar
    '';
    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ pkg-config ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libsecret ];

    passthru.tests.smoke =
      runCommand "httpcraft-smoke"
        {
          nativeBuildInputs = [
            finalAttrs.finalPackage
            python3
          ];
        }
        ''
          set -eu

          export HOME="$TMPDIR/httpcraft-home"
          export HTTPCRAFT_FIXTURE="${./tests/fixtures/test-config.yaml}"
          mkdir -p "$HOME"
          cd "$TMPDIR"

          python3 - <<'PY'
          import os
          import shutil
          import subprocess
          from pathlib import Path

          workdir = Path(os.environ["TMPDIR"]) / "httpcraft-smoke"
          workdir.mkdir()
          config = workdir / "test-config.yaml"
          shutil.copyfile(os.environ["HTTPCRAFT_FIXTURE"], config)

          def run(*args):
              return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30)

          assert run("httpcraft", "--version").stdout.strip() == "1.0.0"
          assert run("httpcraft", "completion", "zsh").stdout.startswith("#compdef httpcraft")

          api_names = run("httpcraft", "--config", str(config), "--get-api-names")
          assert api_names.stdout.strip() == "jsonplaceholder"

          endpoint_names = run(
              "httpcraft",
              "--config",
              str(config),
              "--get-endpoint-names",
              "jsonplaceholder",
          )
          assert set(endpoint_names.stdout.split()) == {"getTodo", "createPost"}

          config.write_text(
              config.read_text()
              + """

          plugins:
            - name: oauth2
              config:
                tokenStorage: memory
          """
          )
          dry_run = run(
              "httpcraft",
              "--config",
              str(config),
              "--dry-run",
              "jsonplaceholder",
              "getTodo",
          )
          assert "[DRY RUN] GET https://jsonplaceholder.typicode.com/todos/1" in dry_run.stderr
          PY

          mkdir -p "$out"
          touch "$out/passed"
        '';

    meta = {
      description = "A powerful CLI tool for HTTP API testing and automation";
      homepage = "https://github.com/samjwillis97/nix-config/tree/main/packages/httpcraft";
      license = lib.licenses.mit;
      mainProgram = "httpcraft";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  });
in
httpcraft
