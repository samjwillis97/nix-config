{
  config = {
    wsl.enable = true;
    wsl.defaultUser = "sam";

    system.stateVersion = "26.05";

    my = {
      users = [ "sam" ];
      dix.enable = true;
    };
  };
}
