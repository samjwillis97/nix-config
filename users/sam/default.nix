{ config, pkgs, ... }:
{
  isNormalUser = true;
  uid = 1000;
  shell = pkgs.zsh;
  initialPassword = "nixos";
  extraGroups = [
    "wheel"
  ]
  ++ (
    if
      (
        config.my.virtualisation.containers.enable
          && config.my.virtualisation.containers.backend == "docker"
      )
    then
      [ "docker" ]
    else
      [ ]
  );

  openssh = {
    authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2FeFN6YQEUr22lJCeuQHcDawLuAPnoizlZLJOwhch4 sam@williscloud.org"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYyMM/qTTLsXdPvvfkhdufg9gLYOI2y8d1oDpAgI0ft samjwillis97@gmail.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENzw8pIt2UVGWcXUx4E4AxxWj8zA+DLZSp0y7RGK5VW samuel.willis@nib.com.au"
    ];
  };
}
