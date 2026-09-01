{ config
, lib
, # pkgs,
  # microvmGuests,
  # mkMicrovmGuest,
  ...
}:
let
  cfg = config.my.microvms;

  # guests = lib.mapAttrs
  #   (name: guestCfg: {
  #     evaluation = mkMicrovmGuest {
  #       inherit name;
  #       hostPkgs = pkgs;
  #       guestModule = microvmGuests.${name};
  #       deploymentModule =
  #         { ... }:
  #         {
  #           my.microvmHost = {
  #             workspace = guestCfg.workspace;
  #             sshPort = guestCfg.sshPort;
  #           };
  #         };
  #     };
  #   })
  #   cfg.guests;
in
{
  options.my.microvms = {
    enable = lib.mkEnableOption "MicroVM hosting (microvm.nix on macOS)";

    guests = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
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

    evaluatedGuests = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      default = { };
      internal = true;
      description = "The evaluated Linux guest configurations (name -> nixosSystem).";
    };
  };
  config = lib.mkIf cfg.enable {
    # Publish the evaluated guests for introspection (mirrors the NixOS
    # adapter's `microvm.vms.<name>.evaluatedConfig`).
    # my.microvms.evaluatedGuests = lib.mapAttrs (_name: guest: guest.evaluation) guests;
  };
}
