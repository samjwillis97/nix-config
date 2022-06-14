{ config, pkgs, ... }: {
  programs.firefox = {
    enable = true;
    extensions = with pkgs.nur.repos.rycee.firefox-addons; [
      decentraleyes
      ublock-origin
      multi-account-containers
      privacy-badger
      bitwarden
    ];

    profiles.sam = {
      bookmarks = {
      };
      settings = {
      };
    };
  };
}
