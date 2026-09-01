{ config
, lib
, ...
}:
let
  # Locally administered MAC address derived from the guest host name so each
  # guest gets a stable, unique NIC.
  mac =
    let
      hash = builtins.hashString "sha256" config.networking.hostName;
      byte = offset: builtins.substring offset 2 (hash + hash);
    in
    "02:00:00:00:${byte 8}:${byte 10}";
in
{
  options.my.microvmHost = {
    workspace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Host directory shared read-write into the guest at /home/sam/workspace.
        Set by the host adapter; null disables the share.
      '';
    };

    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Host-side TCP port forwarded to the guest's SSH (port 22).";
    };
  };

  config = {
    system.stateVersion = lib.mkDefault "24.11";

    microvm = {
      # QEMU runs on both NixOS and macOS (HVF acceleration on Apple Silicon)
      # and supports user networking, deterministic port forwarding and 9p
      # shares without extra services on the host.
      hypervisor = "qemu";

      interfaces = [
        {
          type = "user";
          id = "qemu";
          inherit mac;
        }
      ];

      forwardPorts = [
        {
          host.address = "127.0.0.1";
          host.port = config.my.microvmHost.sshPort;
          guest.port = 22;
        }
      ];

      # Read-only share of the host's /nix/store plus a writable overlay so the
      # guest can install packages without modifying the shared store.
      shares = [
        {
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "9p";
        }
      ]
      ++ lib.optionals (config.my.microvmHost.workspace != null) [
        {
          tag = "workspace";
          source = config.my.microvmHost.workspace;
          mountPoint = "/home/sam/workspace";
          proto = "9p";
        }
      ];

      writableStoreOverlay = "/nix/.rw-store";

      volumes = [
        {
          image = "nix-store-overlay.img";
          mountPoint = config.microvm.writableStoreOverlay;
          size = 2048;
        }
      ];
    };

    programs.zsh.enable = true;

    # The guest store is an overlay on a read-only share; automatic GC and
    # optimisation would fight it and slow startup.
    nix.gc.automatic = lib.mkForce false;
    nix.optimise.automatic = lib.mkForce false;

    # SSH server so hosts can log in through the forwarded port.
    services.openssh.enable = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
