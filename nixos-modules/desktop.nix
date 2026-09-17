{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.desktop.enable {
    environment.systemPackages = with pkgs; [
      wl-clipboard
      mako # notifications
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
      swaylock.enableGnomeKeyring = true;
    };

    # allows home manager
    security.polkit.enable = true;

    # Window manager
    programs.sway = {
      enable = true;
      package = pkgs.swayfx;
      wrapperFeatures.gtk = true;
    };

    # screen sharing
    xdg.portal = {
      enable = true;
      wlr.enable = true;
    };
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # systemd services
    # kanshi is an output configuration daemon
    systemd.user.services.kanshi = {
      description = "kanshi daemon";
      environment = {
        WAYLAND_DISPLAY = "wayland-1";
        DISPLAY = ":0";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.kanshi} -c kanshi_config_file";
      };
    };

    # greeter
    programs.regreet.enable = true;
  };
}
