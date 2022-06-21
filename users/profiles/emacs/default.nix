{ config, lib, pkgs, inputs, ... }:
let 
  name = "doom-install-script";
  mkDoomScript = name: pkgs.writeShellScript "${name}.sh" ''
      if [ ! -d "$HOME/.config/emacs" ]; then
        ${pkgs.git}/bin/git clone --depth=1 --single-branch "https://github.com/hlissner/doom-emacs" "$HOME/.config/emacs"
        ${pkgs.git}/bin/git clone "https://github.com/hlissner/doom-emacs-private" "$HOME/.config/doom"
      fi
  '';
in 

with lib;

{
  nixpkgs.overlays = [ inputs.emacs-overlay.overlay ];

  home.packages = with pkgs; [
    ## Emacs itself
    binutils       # native-comp needs 'as', provided by this
    # 29 + pgtk + native-comp
    # ((emacsPackagesFor emacsPgtkNativeComp).emacsWithPackages (epkgs: [
    ((emacsPackagesFor emacsPgtkGcc).emacsWithPackages (epkgs: [
      epkgs.vterm
    ]))

    ## Doom dependencies
    git
    (ripgrep.override {withPCRE2 = true;})
    gnutls              # for TLS connectivity

    ## Optional dependencies
    fd                  # faster projectile indexing
    imagemagick         # for image-dired
    pinentry_emacs      # in-emacs gnupg prompts
    zstd                # for undo-fu-session/undo-tree compression

    ## Module dependencies
    # :checkers spell
    (aspellWithDicts (ds: with ds; [
      en en-computers en-science
    ]))
    # :tools editorconfig
    editorconfig-core-c # per-project style config
    # :tools lookup & :lang org +roam
    sqlite
    # :lang latex & :lang org (latex previews)
    texlive.combined.scheme-medium
    # :lang beancount
    # beancount
    # unstable.fava  # HACK Momentarily broken on nixos-unstable
    emacs-all-the-icons-fonts
  ];

  systemd.user.services = {
    doom-emacs-install =  {
      Unit = {
        Description = "Install Doom Emacs";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };

      Service = {
        ExecStart = "${mkDoomScript name}";
      };
    };
  };
}
