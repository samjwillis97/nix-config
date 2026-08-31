# pre-assigned user on work macbook
{ lib, ... }:
{
  my.firefox.enable = false;
  home = {
    username = "samuel.willis";
    homeDirectory = lib.mkForce "/Users/samuel.willis";
    stateVersion = "23.11";
  };
}
