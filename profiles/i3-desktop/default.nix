{ config, lib, pkgs, self, ...}: {
  boot.kernelParams = lib.optionals config.services.greetd.enable [ "quiet" ];

  services = {
    greetd = {
      enable = true;
      settings = rec {
        initial_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sx";
          user = "greeter";
        };
        default_session = initial_session;
      };
      vt = 7;
    };

    xserver = {
      enable = true;
      displayManager = {
        sx.enable = true;
      };
    };
  };
}
