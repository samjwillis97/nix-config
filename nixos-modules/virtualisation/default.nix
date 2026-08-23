{ lib, config, ... }:
{
  options.my.virtualisation = {
    docker = {
      enable = lib.mkEnableOption "Docker support";
    };
  };

  config = lib.mkIf config.my.virtualisation.docker.enable {
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";
  };
}
