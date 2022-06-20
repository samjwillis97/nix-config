{ config, lib, pkgs, self, ... }:
let
  # videoDrivers = super.services.xserver.videoDrivers or [ ];
  # backend = 
  #   if (builtins.elem "nvidia" videoDrivers)
  #   then "xrender"
  #   else "glx";
  backend= "glx";
in {
  services.picom = {
    inherit backend;

    enable = true;
    experimentalBackends = true;
    fade = true;
    fadeDelta = 2;
    vSync = true;
    extraOptions = ''
      unredir-if-possible = true;
      unredir-if-possible-exclude = [ "name *= 'Firefox'" ];
    '';
  };
}
