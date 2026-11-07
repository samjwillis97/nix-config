{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "observability";

  nodes.machine =
    _:
    let
      fakeAmp = pkgs.writeText "fake-amp.py" ''
        import json
        import sys

        record = {
            "argv": sys.argv[1:],
            "stdin": sys.stdin.read(),
        }
        with open("/var/lib/triage/amp-invocations.jsonl", "a") as handle:
            handle.write(json.dumps(record) + "\n")
        print(
            "https://ampcode.com/threads/T-01234567-89ab-cdef-0123-456789abcdef",
            file=sys.stderr,
        )
      '';

      amp = pkgs.writeShellScriptBin "amp" ''
        exec ${pkgs.python3}/bin/python3 ${fakeAmp} "$@"
      '';
    in
    {
      imports = [ ./default.nix ];

      networking.hostName = "machine";

      my.observability = {
        logs = {
          enable = true;
          retention = "1d";
          minFreeDiskSpace = "64MB";
          mcp.enable = true;
        };
        probe.enable = true;
        triage = {
          enable = true;
          ampPackage = amp;
          apiKeyFile = pkgs.writeText "fake-amp-key" "test-key";
          runnerId = "teeny";
          runnerDir = "/var/lib/amp/code/code/github.com/samjwillis97/nix-config";
          interval = "1h";
          window = "1m";
          threshold = 2;
          cooldownSeconds = 60;
          continueCooldownSeconds = 60;
          maxPerHour = 10;
          maxPerDay = 20;
          maxActionsPerRun = 1;
          query = ''_time:1m _HOSTNAME:"machine" _SYSTEMD_UNIT:observability-test.service PRIORITY:<=3 | stats by (_HOSTNAME, _SYSTEMD_UNIT) count() as errors | filter errors:>=2'';
        };
      };

      users.users.probeclient = {
        isNormalUser = true;
        extraGroups = [ "probe" ];
      };

      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];

      systemd.services.observability-test = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.SyslogLevel = "err";
        script = ''
          for i in 1 2 3 4 5; do
            echo "observability probe error $i" >&2
          done
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("victorialogs.service")
    machine.wait_for_unit("systemd-journal-upload.service")
    machine.wait_for_unit("observability-test.service")
    machine.wait_for_unit("teeny-probe.socket")

    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:9428/health",
        timeout=30,
    )
    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:8081/health/liveness",
        timeout=30,
    )

    # The uploader must reach VictoriaLogs and preserve the unit field.
    machine.wait_until_succeeds(
        "curl -fsS --data-urlencode 'query=_SYSTEMD_UNIT:observability-test.service' "
        "http://127.0.0.1:9428/select/logsql/query "
        "| grep -F 'observability probe error'",
        timeout=90,
    )

    # The MCP server answers an initialize request with its identity.
    machine.succeed(
        "curl -fsS -X POST http://127.0.0.1:8081/mcp "
        "-H 'Content-Type: application/json' "
        "-H 'Accept: application/json, text/event-stream' "
        "-d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\","
        "\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},"
        "\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}' "
        "| grep -F '\"name\":\"VictoriaLogs\"'"
    )

    # The probe user has journal access; the client user has only the socket group.
    machine.succeed("id -nG probe | grep -qw systemd-journal")
    machine.succeed("id -nG probeclient | grep -qw probe")
    machine.succeed("test \"$(stat -c %a /run/teeny-probe/probe.sock)\" = 660")

    machine.succeed(
        "su -s ${pkgs.bashInteractive}/bin/bash probeclient -c "
        "'/run/current-system/sw/bin/teeny-probe ping' "
        "| grep -F 'probe user: probe'"
    )
    machine.succeed(
        "su -s ${pkgs.bashInteractive}/bin/bash probeclient -c "
        "'/run/current-system/sw/bin/teeny-probe journal "
        "--unit observability-test.service --since=-5m --limit 10' "
        "| grep -F 'observability probe error'"
    )
    machine.succeed(
        "su -s ${pkgs.bashInteractive}/bin/bash probeclient -c "
        "'/run/current-system/sw/bin/teeny-probe unit-status "
        "observability-test.service' "
        "| grep -F 'Active: active'"
    )
    machine.succeed(
        "su -s ${pkgs.bashInteractive}/bin/bash probeclient -c "
        "'/run/current-system/sw/bin/teeny-probe disk' "
        "| grep -F 'Filesystem'"
    )

    # Path traversal and command injection are rejected by the broker.
    machine.fail(
        "su -s ${pkgs.bashInteractive}/bin/bash probeclient -c "
        "'/run/current-system/sw/bin/teeny-probe unit-status ../../etc/passwd'"
    )
    machine.fail(
        "su -s ${pkgs.bashInteractive}/bin/bash probeclient -c "
        "'/run/current-system/sw/bin/teeny-probe journal --unit \"bad;rm -rf /\"'"
    )

    # The timer exists and a dispatcher run creates exactly one thread for the
    # alert, even when it is run again inside the cooldown.
    machine.wait_for_unit("triage-dispatcher.timer")
    machine.succeed("systemctl is-active triage-dispatcher.timer")

    machine.succeed("systemctl start triage-dispatcher.service")
    machine.wait_until_succeeds(
        "test -s /var/lib/triage/amp-invocations.jsonl",
        timeout=60,
    )
    machine.succeed(
        "grep -F 'runner:teeny' /var/lib/triage/amp-invocations.jsonl"
    )
    machine.succeed(
        "grep -F 'observability-test.service' "
        "/var/lib/triage/amp-invocations.jsonl"
    )
    machine.succeed(
        "test \"$(grep -c 'runner:teeny' "
        "/var/lib/triage/amp-invocations.jsonl)\" -eq 1"
    )

    machine.succeed("systemctl start triage-dispatcher.service")
    machine.succeed(
        "test \"$(grep -c 'runner:teeny' "
        "/var/lib/triage/amp-invocations.jsonl)\" -eq 1"
    )
  '';
}
