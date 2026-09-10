{
  lib,
  pkgs,
  fEnabled,
}:
let
  common = builtins.readFile ./scripts/common.sh;

  tmux-session-track = pkgs.writeShellApplication {
    name = "tmux-session-track";
    runtimeInputs = [ pkgs.coreutils ];
    text = common + "\n" + builtins.readFile ./scripts/session-track.sh;
  };

  tmux-session-track-clean = pkgs.writeShellApplication {
    name = "tmux-session-track-clean";
    runtimeInputs = [ pkgs.coreutils ];
    text = common + "\n" + builtins.readFile ./scripts/session-track-clean.sh;
  };

  tmux-session-list = pkgs.writeShellApplication {
    name = "tmux-session-list";
    runtimeInputs = [
      pkgs.tmux
      pkgs.coreutils
    ];
    text = common + "\n" + builtins.readFile ./scripts/session-list.sh;
  };

  tmux-session-picker = pkgs.writeShellApplication {
    name = "tmux-session-picker";
    runtimeInputs = [
      pkgs.tmux
      pkgs.coreutils
      pkgs.fzf
      tmux-session-list
    ]
    ++ lib.optional fEnabled pkgs.f;
    text =
      lib.replaceStrings
        [ "@findBinding@" ]
        [ (lib.optionalString fEnabled ''fzf_args+=(--bind="ctrl-f:become(f -l)")'') ]
        (builtins.readFile ./scripts/session-picker.sh);
  };
in
{
  inherit
    tmux-session-track
    tmux-session-track-clean
    tmux-session-list
    tmux-session-picker
    ;
}
