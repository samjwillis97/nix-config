{ config, lib, pkgs, ... }:
let
  shortPath = with lib.strings;
    (path: concatStringsSep "/" (map (substring 0 1) (splitString "/" path)));
in {
  programs.i3status-rust = {
    enable = true;
    package = pkgs.i3status-rust;
    bars =
    let
      windowBlock = {
        block = "focused_window";
        max_width = 50;
        show_marks = "visible";
      };

      netBlocks = {
        block = "net";
        hide_missing = true;
        hide_inactive = true;
        format = "{ip} {speed_down;K*b} {graph_down;K*b}";
        interval = 5;
      };

      disksBlocks = {
          block = "disk_space";
          info_type = "available";
          unit = "GB";
          interval = 20;
          warning = 20;
          alert = 10;
          # format = "{icon} ${shortPath} {available}";
      };
      
      memoryBlock = {
        block = "memory";
        display_type = "memory";
        format_mem = "{mem_used_percents}";
        format_swap = "{swap_used_percents}";
      };

      cpuBlock = {
        block = "cpu";
        interval = 1;
      };
      
      loadBlock = {
        block = "load";
        interval = 1;
        format = "{1m}";
      };

      temperatureBlock = {

      };

      soundBlock = {
        block = "sound";
        max_vol = 100;
      };

      timeBlock = {
        block = "time";
        interval = 5;
        format = "%a %d/%m %R";
      };
    in {
      i3 = {
        # inherit settings;

        blocks = lib.lists.flatten [
          windowBlock
          disksBlocks
          memoryBlock
          cpuBlock
          loadBlock
          soundBlock
          timeBlock
        ];
      };
    };
  };
}
