{ config
, lib
, pkgs
, ...
}:
{
  system.defaults.dock = {
    enable-spring-load-actions-on-all-items = true;
    appswitcher-all-displays = true;
    autohide = false;
    dashboard-in-overlay = false;
    expose-group-apps = true;
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
      (
        if config.my.work.enable then
          "/Applications/Google Chrome.app"
        else
          "${pkgs.firefox-bin}/Applications/Firefox.app"
      )
      "/system/Applications/Messages.app/"
      "/system/Applications/Calendar.app/"
      "/system/Applications/Notes.app/"
      "/system/Applications/Reminders.app/"
      (lib.optionalString config.my.work.enable "${pkgs.slack}/Applications/Slack.app")
      "${pkgs.ghostty-bin}/Applications/Ghostty.app"
      "/system/Applications/Music.app"
      "/system/Applications/iPhone Mirroring.app/"
      "/Applications/1Password.app"
      "/system/Applications/System Settings.app/"
    ];
    persistent-others = [ "~/Downloads" ];
  };
}
