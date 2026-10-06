{
  config,
  secretModules,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    secretModules.tailscale
  ];

  config = {
    services.displayManager.noctalia-greeter.settings.output = {
      layout = "DP-3:0,0; DP-2:2560,0";
      width = 2560;
      height = 1440;
      refresh_rate = 180;
      scales = "DP-3:1; DP-2:1";
    };

    my = {
      users = [ "sam" ];
      dix.enable = true;
      home-manager.enable = true;

      styling.enable = true;

      gaming.enable = true;

      desktop.enable = true;

      tailscale = {
        enable = true;
        authKeyFile = config.sops.secrets."tailscale-auth-key".path;
      };

      virtualisation.containers.enable = true;

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
  };
}
