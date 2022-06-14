{ config, lib, pkgs, ... }: {
  programs.rofi = {
    enable = true;
    terminal = "${pkgs.alacritty}/bin/alacritty";
    theme = "android_notification";
    # theme = ./themes/dracula.rasi;
    package = with pkgs; rofi.override { plugins = [ rofi-calc rofi-emoji ]; };
    extraConfig = { modi = "drun"; };
  };
}
