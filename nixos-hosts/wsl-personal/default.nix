{
  config,
  inputs,
  secretModules,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    secretModules.tailscale
  ];

  config = {
    nixpkgs.hostPlatform = {
      system = "x86_64-linux";
    };

    wsl.enable = true;
    wsl.defaultUser = "sam";

    system.stateVersion = "26.05";
    environment.systemPackages = [
      pkgs.xrdb
      pkgs.xmodmap
      (pkgs.writeShellScriptBin "startxfce-vcxsrv" ''
        set -eu

        display_host="$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{ print $3; exit }')"
        if [ -z "$display_host" ]; then
          echo "Unable to determine the WSL2 Windows host gateway." >&2
          exit 1
        fi

        export DISPLAY="''${VCXSRV_DISPLAY:-$display_host:0.0}"
        unset WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XFCE4_SESSION_COMPOSITOR
        export GDK_BACKEND=x11
        export QT_QPA_PLATFORM=xcb
        export XDG_SESSION_TYPE=x11
        export XDG_CURRENT_DESKTOP=XFCE
        export XDG_SESSION_DESKTOP=xfce

        exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.runtimeShell} ${pkgs.xfce4-session.xinitrc}
      '')
    ];

    environment.extraInit = ''
      if [ -n "''${WSL_DISTRO_NAME:-}" ]; then
        display_host="$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{ print $3; exit }')"
        if [ -n "$display_host" ]; then
          export DISPLAY="''${VCXSRV_DISPLAY:-$display_host:0.0}"
          unset WAYLAND_DISPLAY
          export GDK_BACKEND=x11
          export QT_QPA_PLATFORM=xcb
        fi
      fi
    '';

    my = {
      users = [ "sam" ];
      dix.enable = true;
      home-manager.enable = true;
      styling.enable = true;

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };

      deploy-rs = {
        enable = true;
        githubActions.enable = true;
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2FeFN6YQEUr22lJCeuQHcDawLuAPnoizlZLJOwhch4 sam@williscloud.org"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYyMM/qTTLsXdPvvfkhdufg9gLYOI2y8d1oDpAgI0ft samjwillis97@gmail.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK+XxL2uM1FT0dR3T5cOJxJd+9luPMctdZd+O2LlJsRk sam@Sams-MacBook-Air.local"
          # Deploy RS
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZUYj/cMiEqPoxH7Uut5VS9Phl2dtCWMOxKf8YyCuY/ sam@williscloud.org"
        ];
      };
    };

    services.xserver.enable = false;
    services.xserver.desktopManager.xfce = {
      enable = true;
      enableWaylandSession = false;
    };

  };
}
