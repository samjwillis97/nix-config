{ config
, lib
, modulesPath
, ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      kernelModules = [ ];
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/53f131b4-97ca-4dd1-b782-0539d546ab84";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/A655-1F00";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [{ device = "/dev/disk/by-uuid/39d56bfa-d378-4e11-a547-b2c15e376f2a"; }];

  networking = {
    useDHCP = lib.mkDefault true;
    interfaces.enp2s0.useDHCP = lib.mkDefault true;
    interfaces.wlp1s0.useDHCP = lib.mkDefault true;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  system.stateVersion = "24.05";
}
