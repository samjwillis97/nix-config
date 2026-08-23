{ pkgs, ... }:
{
  sops = {
    useSystemdActivation = true;

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
  };

  environment.systemPackages = with pkgs; [
    age
  ];
}
