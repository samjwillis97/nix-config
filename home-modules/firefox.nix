{
  config,
  pkgs,
  lib,
  ...
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  options.my.firefox = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.desktop.enable;
      description = "Enable ";
    };
  };

  config = lib.mkIf config.my.firefox.enable (
    lib.mkMerge [
      {
        programs.firefox = {
          enable = true;

          profiles.default = {
            id = 0;

            extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
              decentraleyes
              onepassword-password-manager
              multi-account-containers
              ublock-origin
              i-dont-care-about-cookies
              cookie-autodelete
              terms-of-service-didnt-read
              sponsorblock
              okta-browser-plugin
              tree-style-tab
            ];

            search = {
              force = true;
              default = "ddg";
              order = [ "ddg" ];
              engines = {
                "bing".metaData.hidden = true;
                "ebay".metaData.hidden = true;
                "google".metaData.hidden = true;
                "wikipedia".hidden = true;
              };
            };

            bookmarks = {
              force = true;

              settings = [
                {
                  name = "Duck Duck Go";
                  keyword = "d";
                  url = "https://duckduckgo.com/?q=%s";
                }
                {
                  name = "Google Search";
                  keyword = "g";
                  url = "https://www.google.com.au/search?q=%s";
                }
                {
                  name = "Github Code Search";
                  keyword = "ghrs";
                  url = "https://github.com/search?type=repositories&q=%s";
                }
                {
                  name = "Github Code Search";
                  keyword = "ghcs";
                  url = "https://github.com/search?type=code&q=%s";
                }
                {
                  name = "Nix Pkg Search";
                  keyword = "np";
                  url = "https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&query=%s";
                }
                {
                  name = "Nix Options Search";
                  keyword = "no";
                  url = "https://search.nixos.org/options?channel=unstable&from=0&size=50&sort=relevance&query=%s";
                }
                {
                  name = "Nix Home Manager Options Search";
                  keyword = "hm";
                  url = "https://home-manager-options.extranix.com/?query=%s";
                }
                {
                  name = "OSRSWiki";
                  keyword = "osrs";
                  url = "https://oldschool.runescape.wiki/?search=%s&title=Special%3ASearch&fulltext=Search";
                }
              ];
            };

            settings = {
              "browser.quitShortcut.disabled" = true;
              "general.autoScroll" = true;
            };
          };
        };
      }

      (lib.mkIf isDarwin {
        programs.firefox.package = pkgs.firefox-bin;
      })

      (lib.mkIf config.stylix.enable {
        stylix.targets.firefox.profileNames = [ "default" ];
      })
    ]
  );
}
