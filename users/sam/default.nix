{ hmUsers, ... }:
{
  home-manager.users = { inherit (hmUsers) sam; };

  users.users.sam = {
    password = "nixos";
    description = "Sam Willis";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
}
