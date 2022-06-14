{ suites, ... }:
{
  imports = [
    ./configuration.nix
  ] ++ suites.i3Base;

  bud.enable = true;
  bud.localFlakeClone = "/home/sam/nix-config";
}
