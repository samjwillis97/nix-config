{ config, lib, pkgs, self, ... }: {
  services = with pkgs; {
    pipewire = {
      enable = true;
      # audio.enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      # wireplumber.enable = true;
    };
    # amixer.enable = true;
  };
}
