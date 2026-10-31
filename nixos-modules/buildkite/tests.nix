{ pkgs, ... }:
let
  fakeBuildkiteAgent = pkgs.writeShellScriptBin "buildkite-agent" ''
    set -eu

    test "$1" = start
    test "$2" = --config
    config="$3"
    test -r "$config"

    ${pkgs.gnugrep}/bin/grep -Fx 'token="synthetic-buildkite-token"' "$config" >/dev/null
    ${pkgs.gnugrep}/bin/grep -Fx 'name="%hostname-test-%n"' "$config" >/dev/null
    ${pkgs.gnugrep}/bin/grep -Fx 'tags="queue=test"' "$config" >/dev/null
    ${pkgs.gnugrep}/bin/grep -Fx 'build-path="/var/lib/buildkite-agent-test/builds"' "$config" >/dev/null
    test "$(${pkgs.coreutils}/bin/stat -c %a "$config")" = 600
    test "$(${pkgs.coreutils}/bin/stat -c %a /var/lib/buildkite-agent-test)" = 700
    ${pkgs.coreutils}/bin/id -nG buildkite-agent-test | ${pkgs.gnugrep}/bin/grep -Fwq buildkite-agents

    touch /var/lib/buildkite-agent-test/agent-started
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
in
pkgs.testers.runNixOSTest {
  name = "buildkite-agents";

  nodes = {
    machine = {
      imports = [ ./default.nix ];

      environment.etc."buildkite-token".text = "synthetic-buildkite-token\n";

      services.buildkite-agents.test.package = fakeBuildkiteAgent;

      my.buildkite = {
        enable = true;
        tokenFile = "/etc/buildkite-token";
        agents.test.tags.queue = "test";
      };
    };

    disabled =
      { config, ... }:
      {
        imports = [ ./default.nix ];

        assertions = [
          {
            assertion =
              !(config.systemd.services ? buildkite-agent-test)
              && !(config.users.users ? buildkite-agent-test)
              && !(config.users.groups ? buildkite-agents);
            message = "Disabled Buildkite agents must not create users, groups, or services.";
          }
        ];
      };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("buildkite-agent-test.service")
    machine.wait_until_succeeds("test -e /var/lib/buildkite-agent-test/agent-started", timeout=30)
    machine.succeed("test $(stat -c %a /var/lib/buildkite-agent-test) = 700")
    machine.succeed("test $(stat -c %a /var/lib/buildkite-agent-test/buildkite-agent.cfg) = 600")
    machine.succeed("test $(systemctl show -p User --value buildkite-agent-test.service) = buildkite-agent-test")
    machine.succeed("! systemctl cat buildkite-agent-test.service | grep -F synthetic-buildkite-token")
    machine.succeed("id -nG buildkite-agent-test | tr ' ' '\\n' | grep -Fx buildkite-agents")

    disabled.start()
    disabled.succeed("! systemctl list-unit-files | grep -q '^buildkite-agent-'")
  '';
}
