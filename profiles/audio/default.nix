{ config, lib, pkgs, self, ... }: {
  security.rtkit.enable = true;

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

  environment = {
    systemPackages = with pkgs; [
      pavucontrol
    ];
  };
}
