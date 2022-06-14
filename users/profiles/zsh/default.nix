{ configs, pkgs, ... }:
let
  initExtraBeforeCompInit = ''
    HYPHEN_INSENSITIVE="true"
    ENABLE_CORRECTION="true"
    COMPLETION_WAITING_DOTS="true"
    export EDITOR='vim'
  '';
in {
  programs.zsh = {
    inherit initExtraBeforeCompInit;
    enable = true;
    history = {
      size = 10000;
    };
    enableAutosuggestions= true;
    enableSyntaxHighlighting = true;
    enableCompletion = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "ys";
    };
  };
}
