{ lib, config, ... }:
{
  options.my.virtualisation = {
    containers = {
      enable = lib.mkEnableOption "Container support";

      backend = lib.mkOption {
        type = lib.types.enum [
          "docker"
          "podman"
        ];
        default = "podman";
      };
    };
  };

  config = lib.mkIf config.my.virtualisation.containers.enable {
    virtualisation =
      if config.my.virtualisation.containers.backend == "podman" then
        {
          podman = {
            enable = true;
            dockerCompat = true;

            defaultNetwork.settings = {
              dns_enabled = true;
            };
          };
          oci-containers.backend = "podman";
        }
      else
        {
          docker.enable = true;
          oci-containers.backend = "docker";
        };
  };
}
