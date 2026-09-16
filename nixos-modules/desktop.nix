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

    # secrets
    services.gnome.gnome-keyring.enable = true;

    # allows the greeter to unlock keyring
    security.pam.services = {
      greetd.enableGnomeKeyring = true;
      swaylock.enableGnomeKeyring = true;
    };

    # allows home manager
    security.polkit.enable = true;

    programs.sway = {
      enable = true;
      # package = pkgs.swayfx;
      wrapperFeatures.gtk = true;
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
