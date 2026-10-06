{
  config,
  lib,
  pkgs,
  ...
}:
let
  desktopMonitors = lib.mapAttrsToList (
    name: monitor: monitor // { inherit name; }
  ) config.my.desktop.monitors;
in
{
  config = lib.mkIf config.my.desktop.enable {
    hardware.graphics.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    environment.systemPackages = with pkgs; [
      wl-clipboard
      xwayland-satellite
    ];

    services = {
      # secrets
      gnome.gnome-keyring.enable = true;
      # auto mounting of external storage devices
      udisks2.enable = true;
    };

    # allows the greeter to unlock keyring
    security.pam.services = {
      greetd.enableGnomeKeyring = true;
    };

    # allows home manager
    security.polkit.enable = true;

    programs.niri = {
      enable = true;
      useNautilus = true;
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # greeter
    services.displayManager.noctalia-greeter = {
      enable = true;
      settings.output = lib.mkIf (desktopMonitors != [ ]) (
        let
          primaryMonitor = builtins.head desktopMonitors;
        in
        {
          inherit (primaryMonitor) width height;

          layout = lib.concatMapStringsSep "; " (
            monitor: "${monitor.name}:${toString monitor.x},${toString monitor.y}"
          ) desktopMonitors;
          refresh_rate = primaryMonitor.refreshRate;
          scales = lib.concatMapStringsSep "; " (
            monitor: "${monitor.name}:${toString monitor.scale}"
          ) desktopMonitors;
        }
      );
    };
  };
}
