{ pkgs, ... }:
{
  isNormalUser = true;
  shell = pkgs.zsh;
  initialPassword = "nixos";
  extraGroups = [ "wheel" ];
}
