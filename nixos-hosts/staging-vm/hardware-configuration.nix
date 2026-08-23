{
  nixpkgs.hostPlatform = {
    system = "x86_64-linux";
  };

  virtualisation = {
    diskSize = 20000;
    memorySize = 4096;
    cores = 8;

    sharedDirectories.agenix = {
      source = "/var/agenix";
      target = "/var/agenix";
      securityModel = "none";
    };

    fileSystems."/var/agenix".options = [ "ro" ];
  };

  networking.useDHCP = true;
  hardware.cpu.amd.updateMicrocode = true;

  system.stateVersion = "24.05";
}
