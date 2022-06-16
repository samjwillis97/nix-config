{ config, lib, pkgs, self, ...  }: 
let
  inherit (self) inputs;
in {
  home.packages = [ (pkgs.nerdfonts.override { fonts = [ "Hack" ]; }) ];

  programs.nnn = {
    enable = true;
    package = pkgs.nnn.override ({ withNerdIcons = true; });
    bookmarks = {
      D = "~/Documents";
      d = "~/Downloads";
      p = "~/Projects";
      P = "~/Pictures";
      v = "~/Videos";
      "/" = "/";
    };
    extraPackages = with pkgs; [
      bat
      exa
      fzf
      mediainfo
    ];
    plugins = {
      src = "${inputs.nnn-plugins}/plugins";
      mappings = {
        c = "fzfcd";
        f = "finder";
        o = "fzopen";
        p = "previw-tui";
        t = "nmount";
        v = "imgview";
      };
    };
  };
  # TODO: Block Nesting of NNN in Subshells
}
