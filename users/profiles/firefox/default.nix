{ config, pkgs, ... }: {
  programs.firefox = {
    enable = true;
    extensions = with pkgs.nur.repos.rycee.firefox-addons; [
      decentraleyes
      ublock-origin
      multi-account-containers
      privacy-badger
      user-agent-string-switcher
      bitwarden
    ];

    profiles.sam = {
      bookmarks = {
        "Proton Mail" = {
          keyword = "p";
          url = "https://mail.protonmail.com/u/0/inbox";
        };
        "Duck Duck Go" = {
          keyword = "d";
          url = "https://duckduckgo.com/?q=%s";
        };
        "Nix Pkg Search" = {
          keyword = "np";
          url = "https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&query=%s";
                                                    
        };
        "Nix Options Search" = {
          keyword = "no";
          url = "https://search.nixos.org/options?channel=unstable&from=0&size=50&sort=relevance&query=%s";
                                                  
        };
        "OSRSWiki" = {
          keyword = "osrs";
          url = "https://oldschool.runescape.wiki/?search=%s&title=Special%3ASearch&fulltext=Search";
        };
      };
      settings = {
      };
    };
  };
}
