{
  lib,
  buildGo127Module,
  fetchFromGitHub,
}:

let
  version = "0.1.1";
in
buildGo127Module {
  pname = "unreal-agent";
  inherit version;

  src = fetchFromGitHub {
    owner = "unreallabsai";
    repo = "unreal-agent";
    rev = "v${version}";
    hash = "sha256-L+eWOTFiHTy3oQL9GSeScKxjetZ1x0M9QAKg156oA0E=";
  };

  subPackages = [ "cmd/unreal-agent-runner" ];
  vendorHash = "sha256-JnIySSral40U188nsO+7zt/4404bAGQIXNiMz+/Fbyo=";

  meta = {
    description = "Async-first agent harness";
    homepage = "https://github.com/unreallabsai/unreal-agent";
    license = lib.licenses.mit;
    mainProgram = "unreal-agent-runner";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
