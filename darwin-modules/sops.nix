{ pkgs, ... }:
{
  sops = {
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
  };

  environment.systemPackages = with pkgs; [
    age
  ];
}
