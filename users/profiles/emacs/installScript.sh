#!/usr/bin/env bash
if [ ! -d "$XDG_CONFIG_HOME/emacs" ]; then
	"${pkgs.git}/bin/git clone --depth=1 --single-branch "https://github.com/hlissner/doom-emacs" "$XDG_CONFIG_HOME/emacs"
	"${pkgs.git}/bin/git clone "https://github.com/hlissner/doom-emacs-private" "$XDG_CONFIG_HOME/doom"
fi
