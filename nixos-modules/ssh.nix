{ pkgs, ... }:
{
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  environment.systemPackages = with pkgs; [
    ghostty.terminfo
  ];
}
