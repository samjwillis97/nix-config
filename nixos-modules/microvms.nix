{ config
, lib
, pkgs
, microvmGuests
, mkMicrovmGuest
, ...
}:
let
  cfg = config.my.microvms;

  # Evaluate each selected guest once. The result is a NixOS configuration
  # for the Linux guest running inside this host.
  guests = lib.mapAttrs
    (
      name: guestCfg:
        mkMicrovmGuest {
          inherit name;
          hostPkgs = pkgs;
          guestModule = microvmGuests.${name};
          deploymentModule = {
            my.microvmHost = {
              inherit (guestCfg) workspace sshPort;
            };
          };
        }
    )
    cfg.guests;
in
{
  options.my.microvms = {
    enable = lib.mkEnableOption "MicroVM hosting (microvm.nix)";

    guests = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            autostart = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Start this MicroVM automatically at boot. Coding/agent guests
                should stay false and be started on demand with
                `systemctl start microvm@<name>`.
              '';
            };

            workspace = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Host directory shared read-write into the guest at
                /home/sam/workspace. Only the explicitly listed directory is
                exposed to the guest.
              '';
            };

            sshPort = lib.mkOption {
              type = lib.types.port;
              default = 2222;
              description = "Host-side TCP port forwarded to the guest's SSH (22).";
            };
          };
        }
      );
      default = { };
      description = "Named MicroVM guests this host manages.";
    };
  };

  config = lib.mkMerge [
    {
      microvm.host.enable = cfg.enable;
    }
    (lib.mkIf cfg.enable {
      assertions = lib.mapAttrsToList
        (name: _: {
          assertion = builtins.hasAttr name microvmGuests;
          message = "my.microvms: unknown guest '${name}' (./microvms/guests/${name}/default.nix not found)";
        })
        cfg.guests;

      microvm.vms = lib.mapAttrs
        (name: guestCfg: {
          inherit (guestCfg) autostart;
          evaluatedConfig = guests.${name};
          # restartIfChanged only defaults to true for `config`-based VMs;
          # set it explicitly for evaluatedConfig.
          restartIfChanged = true;
        })
        cfg.guests;
    })
  ];
}
