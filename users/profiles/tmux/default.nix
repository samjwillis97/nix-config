{ config, lib, pkgs, ... }: {
  programs.tmux = {
    enable = true;

    shell = "/run/current-system/sw/bin/zsh";
    plugins = with pkgs; [
      tmuxPlugins.dracula
      tmuxPlugins.sensible
      tmuxPlugins.resurrect
      tmuxPlugins.vim-tmux-navigator
    ];

    extraConfig = ''
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
        | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
      bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "select-pane -L"
      bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "select-pane -D"
      bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "select-pane -U"
      bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "select-pane -R"
      set -g default-terminal "screen-256color"

      set -g mouse on

      bind-key r source-file ~/.tmux.conf \; display-message "~/.tmux.conf reloaded"
    '';
  };
}
