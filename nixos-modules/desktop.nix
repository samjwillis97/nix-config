{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.desktop.enable {
    hardware.graphics.enable = true;

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
      useNautilus = false;
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # greeter
    programs.regreet.enable = true;
  };
}
