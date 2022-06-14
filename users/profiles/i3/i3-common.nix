{ config
, lib
, terminal
, menu
# , pamixer
# , light
# , playerctl
# , fullScreenShot
, areaScreenShot
, browser
, fileManager
, statusCommand
, mod ? "Mod1"
, bars ? [{
    position = "top";
    colors = {
      background = "#282A36";
      statusline = "#F8F8F2";
      separator = "#44475A";
      focusedWorkspace = {
        background = "#44475A";
        border = "#44475A";
        text = "#F8F8F2";
      };
      activeWorkspace = {
        background = "#282A36";
        border = "#44475A";
        text = "#F8F8F2";
      };
      inactiveWorkspace = {
        background = "#282A36";
        border = "#282A36";
        text = "#BFBFBF";
      };
      urgentWorkspace = {
        background = "#FF5555";
        border = "#FF5555";
        text = "#F8F8F2";
      };
      bindingMode = {
        background = "#FF5555";
        border = "#FF5555";
        text = "#F8F8F2";
      };
    };
  }]
, fonts ? { }
, extraBindings ? { }
, extraWindowOptions ? { }
, extraFocusOptions ? { }
, extraModes ? { }
, extraConfig ? ""
, workspaces ? [
  {
      ws = 1;
      name = "1";
    }
    {
      ws = 2;
      name = "2";
    }
    {
      ws = 3;
      name = "3";
    }
    {
      ws = 4;
      name = "4";
    }
    {
      ws = 5;
      name = "5";
    }
    {
      ws = 6;
      name = "6";
    }
    {
      ws = 7;
      name = "7";
    }
    {
      ws = 8;
      name = "8";
    }
    {
      ws = 9;
      name = "9";
    }
  ]
}: let
  mapWorkspacesStr = with builtins;
    with lib.strings;
    { workspaces, prefixKey ? null, prefixCmd }:
    (concatStringsSep "\n" (map
      ({ ws, name }:
        ''
          bindsym ${optionalString (prefixKey != null) "${prefixKey}+"}${
            toString ws
          } ${prefixCmd} "${name}"'')
      workspaces));
in {
  helpers = { inherit mapWorkspacesStr; };
  config = {
    inherit bars fonts menu terminal;

    modifier = mod;

    
    colors = {
      background = "#F8F8F2";
      focused = {
        border				=		"#6272A4";
        background		=		"#6272A4";
        text					=		"#F8F8F2";
        indicator			=		"#6272A4";
        childBorder		=		"#6272A4";
      };
      focusedInactive = {
        border				=		"#44475A";
        background		=		"#44475A";
        text					=		"#F8F8F2";
        indicator			=		"#44475A";
        childBorder		=		"#44475A";
      };
      unfocused = {
        border				=		"#282A36";
        background		=		"#282A36";
        text					=		"#BFBFBF";
        indicator			=		"#282A36";
        childBorder		=		"#282A36";
      };
      urgent = {
        border				=		"#44475A";
        background		=		"#FF5555";
        text					=		"#F8F8F2";
        indicator			=		"#FF5555";
        childBorder		=		"#FF5555";
      };
      placeholder = {
        border				=		"#282A36";
        background		=		"#282A36";
        text					=		"#F8F8F2";
        indicator			=		"#282A36";
        childBorder		=		"#282A36";
      };
    };
    keybindings = ({
      # System Binds
      "${mod}+Shift+q" = "kill"; # Kill Focused Window
      "${mod}+Shift+r" = "restart"; # Restart i3 in Place
      "${mod}+Shift+Control+q" = "exec i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'";
      "${mod}+Return" = "exec ${terminal}";
      "Print" = "exec ${areaScreenShot}"; # Flameshot
      # Rofi
      "${mod}+d" = "exec ${menu} drun";
      "${mod}+Tab" = "exec ${menu} window";
      # Modes
      "${mod}+r" = "mode resize";
      "${mod}+p" = "mode rofi";
      # Change Focus
      "${mod}+h" = "focus left";
      "${mod}+j" = "focus down";
      "${mod}+k" = "focus up";
      "${mod}+l" = "focus right";
      # Resizing
      "${mod}+Control+h" = "resize shrink width 10 px or 10 ppt";
      "${mod}+Control+j" = "resize grow height 10 px or 10 ppt";
      "${mod}+Control+k" = "resize shrink height 10 px or 10 ppt";
      "${mod}+Control+l" = "resize grow width 10 px or 10 ppt";
      # Move Focused Window
      "${mod}+Shift+h" = "move left";
      "${mod}+Shift+j" = "move down";
      "${mod}+Shift+k" = "move up";
      "${mod}+Shift+l" = "move right";
      # Move Workspaces Between Screens
      "${mod}+period" = "move workspace to output right";
      "${mod}+comma" = "move workspace to output left";
      # Splitting
      "${mod}+s" = "split v"; # Horizontal
      "${mod}+v" = "split h"; # Vertical
      # Change Modes
      "${mod}+f" = "fullscreen toggle"; # Fullscreen for Current Container
      "${mod}+Shift+s" = "layout stacking";
      "${mod}+Shift+w" = "layout tabbed";
      "${mod}+Shift+e" = "layout toggle split";
      "${mod}+space" = "floating toggle";
      "${mod}+Shift+space" = "focus mode_toggle";
      # Focus
      # "${mod}+a" = "focus parent";
      # "${mod}+d" = "focus child";
      # Workspaces
      # "${mod}+1" = "workspace number $ws1";
      # "${mod}+2" = "workspace number $ws2";
      # "${mod}+3" = "workspace number $ws3";
      # "${mod}+4" = "workspace number $ws4";
      # "${mod}+5" = "workspace number $ws5";
      # "${mod}+6" = "workspace number $ws6";
      # "${mod}+7" = "workspace number $ws7";
      # "${mod}+8" = "workspace number $ws8";
      # "${mod}+9" = "workspace number $ws9";
    } // extraBindings);

    # TODO: Add PowerManager
    modes = {
      resize = {
        "h" = "resize shrink width 10 px or 10 ppt";
        "j" = "resize grow height 10 px or 10 ppt";
        "k" = "resize shrink height 10 px or 10 ppt";
        "l" = "resize grow width 10 px or 10 ppt";
        "Return" = "mode default";
        "Escape" = "mode default";
        "${mod}+r" = "mode default";
      };
      rofi = {
        "s" = "exec ${menu} ssh";
        "f" = "exec ${menu} filebrowser";
        "c" = "exec ${menu} calc";
        "Return" = "mode default";
        "Escape" = "mode default";
        "${mod}+p" = "mode default";
      };
    };

    gaps = {
      inner = 15;
    };

    window = {
      border = 2;
      hideEdgeBorders = "smart";
      titlebar = false;
    } // extraWindowOptions;

    focus = { followMouse = false; } // extraFocusOptions;
  };

  # Until this issue is fixed we need to map workspaces directly to config file
  # https://github.com/nix-community/home-manager/issues/695
  extraConfig =
    let
      workspaceStr = (builtins.concatStringsSep "\n" [
        (mapWorkspacesStr {
          inherit workspaces;
          prefixKey = mod;
          prefixCmd = "workspace number";
        })
        (mapWorkspacesStr {
          inherit workspaces;
          prefixKey = "${mod}+Shift";
          prefixCmd = "move container to workspace number";
        })
      ]);
    in
    ''
      ${workspaceStr}
      ${extraConfig}
    '';
}
