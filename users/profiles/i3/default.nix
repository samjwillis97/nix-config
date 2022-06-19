{ config, lib, pkgs, ... }: 
let
	mod = "Mod1"; # Alt
  commonOptions = 
    let
      rofi = "${config.programs.rofi.package}/bin/rofi";
    in
    import ./i3-common.nix rec {
      inherit config lib mod;
      
      browser = "firefox";
      fileManager = "${terminal} ${config.programs.nnn.finalPackage}/bin/nnn -a -P p";
      statusCommand = with config;
          "${programs.i3status-rust.package}/bin/i3status-rs ${xdg.configHome}/i3status-rust/config-i3.toml";
      menu = "${rofi} -show";
      terminal = 
        if config.programs.alacritty.enable then
          "${pkgs.alacritty}/bin/alacritty"
        else
          "${pkgs.xterm}/bin/xterm";
      areaScreenShot = "${pkgs.flameshot}/bin/flameshot gui";

      extraBindings = {

      };

      extraModes = {

      };

      extraConfig = ''
        for_window [window_role="pop-up"] floating enable
        for_window [window_role="task_dialog"] floating enable
        for_window [title="Settings"] floating enable
        for_window [window_role="PictureInPicture"] floating enable
        for_window [window_role="PictureInPicture"] sticky enable
      '';
    };
  xsession = "${config.home.homeDirectory}/.xsession";
in {
  imports = [
    ./i3status-rust.nix
  ];

  xsession.enable = true;
  xsession.windowManager.i3 = with commonOptions; {
    enable = true;
    package = pkgs.i3-gaps;

    inherit extraConfig;

    config = commonOptions.config;
  };

  systemd.user.services.wallpaper = {
    Unit = {
      Description = "Set Wallpaper";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install = { WantedBy = [ "graphical-session.target" ]; };

    Service = {
      ExecStart = "${pkgs.feh}/bin/feh --bg-scale ${config.home.homeDirectory}/.wallpaper.png";
      Type = "oneshot";
    };
  };

  home.file.".wallpaper.png".source = ./wallpaper.png;

  home.file.".xinitrc".source = config.lib.file.mkOutOfStoreSymlink xsession;
  xdg.configFile."sx/sxrc".source = config.lib.file.mkOutOfStoreSymlink xsession;

  home.packages = with pkgs; [
    arandr
    libnotify
  ];
}

