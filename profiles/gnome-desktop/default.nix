{ conifg, lib, pkgs, self, ...}:
let
  gnomePackages = with pkgs.gnome; [
    gnome-tweaks
  ];

  gnomeExtensions = with pkgs.gnomeExtensions; [
    blur-my-shell
  ];
in {
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs;
    [ gjs ] ++ gnomePackages ++ gnomeExtensions;

  environment.gnome.excludePackages = with pkgs; [
    gnome.cheese
    gnome-photos
    gnome.gnome-music
    gnome.gedit
    epiphany
    evince
    gnome.gnome-characters
    gnome.totem
    gnome.tali
    gnome.iagno
    gnome.hitori
    gnome.atomix
    gnome.gnome-weather
    gnome.gnome-contacts
    gnome.gnome-maps
    gnome.geary
    gnome-tour
    gnome-connections
  ];
}
