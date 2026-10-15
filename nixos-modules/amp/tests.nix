{ pkgs, ... }:
let
  syntheticAmpApiKey = pkgs.writeText "amp-test-api-key" "synthetic-amp-access-token\n";
  syntheticEmptyAmpApiKey = pkgs.writeText "amp-test-empty-api-key" "";
  syntheticGitHubToken = pkgs.writeText "amp-test-github-token" "synthetic-github-access-token\n";

  fakeAmp = pkgs.writeShellScriptBin "amp" ''
    set -eu

    test "$AMP_API_KEY" = "synthetic-amp-access-token"
    test "$GH_TOKEN" = "synthetic-github-access-token"
    test -r "$CREDENTIALS_DIRECTORY/amp-api-key"
    test -r "$CREDENTIALS_DIRECTORY/github-token"
    test ! -r /run/secrets/amp-api-key
    test ! -r /run/secrets.d/amp-runner-host-readable
    test ! -r /var/lib/sops-nix/amp-runner-host-readable
    test ! -r /var/lib/deploy/amp-runner-host-readable
    test ! -r /data/amp-runner-host-readable
    test ! -r /var/lib/supernote/amp-runner-host-readable
    test ! -r /var/lib/actual/amp-runner-host-readable
    test ! -r /var/lib/postgresql/amp-runner-host-readable
    test ! -r /var/lib/jellyfin/amp-runner-host-readable
    test -w /tmp
    test ! -w /nix/store
    test "$(git config --global --get user.email)" = "amp-test@example.invalid"
    git config --get-urlmatch credential.helper https://github.com/example/repo >/dev/null
    ! git config --get-urlmatch credential.helper https://gitlab.com/example/repo >/dev/null

    touch /var/lib/amp/code/workspace-write-test
    mkdir -p /var/lib/amp/code/direnv-fixture
    printf 'export AMP_TEST_DIRENV=allowed\n' > /var/lib/amp/code/direnv-fixture/.envrc
    ${pkgs.direnv}/bin/direnv allow /var/lib/amp/code/direnv-fixture/.envrc
    ${pkgs.direnv}/bin/direnv exec /var/lib/amp/code/direnv-fixture ${pkgs.bashInteractive}/bin/bash -c 'test "$AMP_TEST_DIRENV" = allowed'

    ${pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' store info
    ${pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' path-info ${pkgs.coreutils} >/dev/null

    printf '%s\n' "$@" > /var/lib/amp/runner-arguments
    touch /var/lib/amp/runner-started
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  mkRunnerNode =
    {
      hostname,
      apiKeyFile ? "/etc/amp-test-api-key",
      restartPolicy ? "always",
    }:
    { ... }:
    {
      imports = [ ./default.nix ];

      _module.args.inputs = {
        "llm-agents".packages.x86_64-linux.amp = fakeAmp;
      };

      networking.hostName = hostname;
      nix.settings.allowed-users = [ "amp" ];
      systemd = {
        tmpfiles.rules = [
          "d /data 0755 root root - -"
          "f /data/amp-runner-host-readable 0444 root root - synthetic"
          "d /var/lib/supernote 0755 root root - -"
          "f /var/lib/supernote/amp-runner-host-readable 0444 root root - synthetic"
          "d /var/lib/actual 0755 root root - -"
          "f /var/lib/actual/amp-runner-host-readable 0444 root root - synthetic"
          "d /var/lib/postgresql 0755 root root - -"
          "f /var/lib/postgresql/amp-runner-host-readable 0444 root root - synthetic"
          "d /var/lib/jellyfin 0755 root root - -"
          "f /var/lib/jellyfin/amp-runner-host-readable 0444 root root - synthetic"
          "d /var/lib/deploy 0755 root root - -"
          "f /var/lib/deploy/amp-runner-host-readable 0444 root root - synthetic"
          "d /var/lib/sops-nix 0755 root root - -"
          "f /var/lib/sops-nix/amp-runner-host-readable 0444 root root - synthetic"
          "d /run/secrets 0755 root root - -"
          "f /run/secrets/amp-api-key 0444 root root - synthetic"
          "d /run/secrets.d 0755 root root - -"
          "f /run/secrets.d/amp-runner-host-readable 0444 root root - synthetic"
        ];
        services = {
          sops-install-secrets.serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.coreutils}/bin/true";
          };
          amp-runner.serviceConfig.Restart = pkgs.lib.mkForce restartPolicy;
        };
      };
      environment.etc = {
        "amp-test-api-key".source = syntheticAmpApiKey;
        "amp-test-empty-api-key".source = syntheticEmptyAmpApiKey;
        "amp-test-github-token".source = syntheticGitHubToken;
      };

      my.amp = {
        enable = true;
        runner = {
          enable = true;
          package = fakeAmp;
          inherit apiKeyFile;
          githubTokenFile = "/etc/amp-test-github-token";
          gitEmail = "amp-test@example.invalid";
        };
      };
    };
in
pkgs.testers.runNixOSTest {
  name = "amp-runner";

  nodes = {
    machine = mkRunnerNode { hostname = "amp-test"; };
    emptyCredentials = mkRunnerNode {
      hostname = "amp-empty";
      apiKeyFile = "/etc/amp-test-empty-api-key";
      restartPolicy = "no";
    };
    missingCredentials = mkRunnerNode {
      hostname = "amp-missing";
      apiKeyFile = "/etc/amp-test-missing-api-key";
      restartPolicy = "no";
    };

    packageOnly =
      { config, ... }:
      {
        imports = [ ./default.nix ];

        _module.args.inputs = {
          "llm-agents".packages.x86_64-linux.amp = fakeAmp;
        };

        my.amp.enable = true;

        assertions = [
          {
            assertion =
              builtins.elem fakeAmp config.environment.systemPackages
              && !(config.systemd.services ? amp-runner)
              && !(config.users.users ? amp);
            message = "Package-only Amp enablement must not create the runner account or service.";
          }
        ];
      };

    disabled =
      { config, ... }:
      {
        imports = [ ./default.nix ];

        _module.args.inputs = {
          "llm-agents".packages.x86_64-linux.amp = fakeAmp;
        };

        assertions = [
          {
            assertion =
              !(builtins.elem fakeAmp config.environment.systemPackages)
              && !(config.systemd.services ? amp-runner)
              && !(config.users.users ? amp);
            message = "Disabled Amp must not install the CLI or create the runner account or service.";
          }
        ];
      };
  };

  testScript = ''
    # Verify staged credentials, host-data denial, Git scoping, Nix daemon access, and workspace writes.
    def test_runner_credentials_and_sandbox(machine):
        machine.start()
        machine.wait_for_unit("amp-runner.service")
        machine.wait_until_succeeds("test -e /var/lib/amp/runner-started", timeout=30)
        machine.succeed("grep -Fx -- '--no-tui' /var/lib/amp/runner-arguments")
        machine.succeed("grep -Fx -- '--runner-id' /var/lib/amp/runner-arguments")
        machine.succeed("grep -Fx -- 'amp-test' /var/lib/amp/runner-arguments")
        machine.succeed("grep -Fx -- '--remote-control-terminal' /var/lib/amp/runner-arguments")
        machine.succeed("grep -Fx -- '--discover-dirs' /var/lib/amp/runner-arguments")
        machine.succeed("grep -Fx -- '4' /var/lib/amp/runner-arguments")
        machine.succeed("test -e /var/lib/amp/code/workspace-write-test")
        machine.succeed("test $(systemctl show -p ProtectSystem --value amp-runner.service) = strict")
        machine.succeed("test $(systemctl show -p NoNewPrivileges --value amp-runner.service) = yes")
        machine.succeed("! systemctl cat amp-runner.service | grep -F synthetic")
        machine.succeed("! id -nG amp | grep -qw wheel")
        machine.succeed("touch /var/lib/amp/state-persistence-fixture")
        machine.succeed("systemctl restart amp-runner.service")
        machine.wait_for_unit("amp-runner.service")
        machine.succeed("test -e /var/lib/amp/state-persistence-fixture")

    # Verify an empty API credential fails before Amp starts.
    def test_empty_credentials_fail_closed(machine):
        machine.start()
        machine.wait_until_succeeds("systemctl is-failed --quiet amp-runner.service", timeout=30)
        machine.succeed("test ! -e /var/lib/amp/runner-started")

    # Verify a missing API credential fails systemd credential loading before Amp starts.
    def test_missing_credentials_fail_closed(machine):
        machine.start()
        machine.wait_until_succeeds("systemctl is-failed --quiet amp-runner.service", timeout=30)
        machine.succeed("test ! -e /var/lib/amp/runner-started")

    test_runner_credentials_and_sandbox(machine)
    test_empty_credentials_fail_closed(emptyCredentials)
    test_missing_credentials_fail_closed(missingCredentials)
  '';
}
