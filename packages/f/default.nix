{ writeShellScriptBin }:

writeShellScriptBin "f" (builtins.readFile ./f.sh)
