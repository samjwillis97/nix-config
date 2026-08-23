{
  nixpkgs.hostPlatform = {
    system = "x86_64-linux";
  };

  virtualisation = {
    diskSize = 20000;
    memorySize = 4096;
    cores = 8;
  };

  networking.useDHCP = true;
  hardware.cpu.amd.updateMicrocode = true;

  system.stateVersion = "24.05";
}
