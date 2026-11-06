{
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.nixos-wsl.nixosModules.default ];

  nixpkgs.hostPlatform = {
    system = "x86_64-linux";
  };

  wsl = {
    enable = true;
    defaultUser = "sam";
    useWindowsDriver = true;
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa
      libvdpau-va-gl
      libva-vdpau-driver
    ];
  };

  environment.sessionVariables = {
    LD_LIBRARY_PATH = [
      "/run/opengl-driver/lib"
      "${pkgs.openssl.out}/lib"
    ];
    GALLIUM_DRIVER = "d3d12";
    # Set to "Nvidia", "Intel", etc. on hybrid-GPU laptops.
    # MESA_D3D12_DEFAULT_ADAPTER_NAME = "Nvidia";
  };

  system.stateVersion = "26.05";

  my = {
    users = [ "sam" ];
    home-manager.enable = true;
    styling.enable = true;
    work.enable = true;
  };
}
