{ pkgs, ... }:
{
  isNormalUser = true;
  shell = pkgs.bash;
  # openssh.authorizedKeys.keys = lib.mkForce (builtins.readFile ./users/${user}/ssh/authorized_keys);
  initialPassword = "nixos";
  extraGroups = [ "wheel" ];
}
