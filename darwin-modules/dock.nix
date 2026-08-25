{
  system.defaults.dock = {
    enable-spring-load-actions-on-all-items = true;
    appswitcher-all-displays = true;
    autohide = false;
    dashboard-in-overlay = false;
    expose-group-by-app = true;
    launchanim = true;
    minimize-to-application = false;
    mru-spaces = false;
    orientation = "left";
    show-process-indicators = true;
    show-recents = false;
    showhidden = false;
    static-only = false;
    tilesize = 48;
    magnification = false;
    largesize = 56;
    persistent-apps = builtins.filter (a: a != "") [
      "/Applications/Google Chrome.app"
      "/system/Applications/Messages.app/"
      "/system/Applications/Calendar.app/"
      "/system/Applications/Notes.app/"
      "/system/Applications/Reminders.app/"
      # "${pkgs.slack}/Applications/Slack.app"
      # "${pkgs.discord}/Applications/Discord.app"
      # "${pkgs.ghostty-bin}/Applications/Ghostty.app"
      "/system/Applications/Music.app"
      "/system/Applications/iPhone Mirroring.app/"
      "/Applications/1Password.app"
      "/system/Applications/System Settings.app/"
    ];
    persistent-others = [ "~/Downloads" ];
  };
}
