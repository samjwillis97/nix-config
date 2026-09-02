{
  inputs,
  config,
  lib,
  ...
}:
let
  pathOrString =
    with lib.types;
    oneOf [
      path
      str
    ];

  secretFileOption =
    name:
    lib.mkOption {
      type = pathOrString;
      description = "Path to the file containing the ${name}";
    };
in
{
  options.my.media.jellyfin = {
    enable = lib.mkEnableOption "jellyfin media server";

    apiKeyFile = secretFileOption "jellyfin API key";

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.path);
      default = { };
      description = "Users to create for jellyfin, with passwords stored in files";
    };

    adminPasswordFile = secretFileOption "jellyfin admin password";

    xtream = {
      baseUrlFile = secretFileOption "Base URL for Xtream plugin";
      usernameFile = secretFileOption "Username for Xtream plugin";
      passwordFile = secretFileOption "Password for Xtream plugin";

      channels = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = "Channels to enable for Xtream plugin, grouped by group ID";
      };
    };

    httpPort = lib.mkOption {
      type = lib.types.int;
      default = 8096;
      description = "Port for jellyfin to listen on";
    };

    openFirewall = lib.mkEnableOption "open firewall for jellyfin, independent of ingress route";

    ingress.enable = lib.mkEnableOption "jellyfin ingress route";
  };

  config = lib.mkIf (config.my.media.enable && config.my.media.jellyfin.enable) (
    lib.mkMerge [
      {
        nixflix.jellyfin = {
          enable = true;
          openFirewall = config.my.media.jellyfin.openFirewall;

          apiKey = {
            _secret = config.my.media.jellyfin.apiKeyFile;
          };

          users = {
            admin = {
              password = {
                _secret = config.my.media.jellyfin.adminPasswordFile;
              };
              policy = {
                isAdministrator = true;
              };
            };
          }
          // (builtins.mapAttrs (_name: user: {
            password = {
              _secret = user.password;
            };
            policy = {
              isAdministrator = false;
            };
          }) config.my.media.jellyfin.users);

          network = {
            internalHttpPort = config.my.media.jellyfin.httpPort;
          };

          system.pluginRepositories = {
            "Jellyfin.XTream" = {
              enabled = true;
              url = "https://kevinjil.github.io/Jellyfin.Xtream/repository.json";
              hash = "sha256-xneshIL76OaYLnFR0Cs3ysbAgS5jvN/4yzoFE5PE3wY=";
            };
          };

          plugins = {
            "Jellyfin Xtream" = {
              package = inputs.nixflix.lib.jellyfinPlugins.fromRepo {
                version = "0.8.1.0";
                hash = "sha256-mcLeVW7nQdaqMYf2UOQSUMtn7zOBi6jOZ35TCTR35vA=";
              };
              config = {
                BaseUrl._secret = config.my.media.jellyfin.xtream.baseUrlFile;
                Username._secret = config.my.media.jellyfin.xtream.usernameFile;
                Password._secret = config.my.media.jellyfin.xtream.passwordFile;

                LiveTv = config.my.media.jellyfin.xtream.channels;

                IsCatchupVisible = false;
                IsSeriesVisible = false;
                IsVodVisible = false;
                IsTmdbVodOverride = true;
              };
            };
          };
        };
      }

      (lib.mkIf config.my.media.jellyfin.ingress.enable {
        my.ingress.routes.jellyfin = {
          upstream = "http://127.0.0.1:${toString config.my.media.jellyfin.httpPort}";
          websockets = true;
        };
      })
    ]
  );
}
