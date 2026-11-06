{
  lib,
  buildGo126Module,
  fetchFromGitHub,
  fuse,
  pkg-config,
}:
let
  version = "2.7.2";
in
buildGo126Module {
  pname = "decypharr";
  inherit version;

  src = fetchFromGitHub {
    owner = "sirrobot01";
    repo = "decypharr";
    rev = "v${version}";
    hash = "sha256-SXEGn5pWBxRPVvGHt2pHCMFnikj+eGKfi9guXcEZDvI=";
  };

  subPackages = [ "." ];

  # The Windows DFS backend is still compiled under cgo and includes <fuse.h>.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ fuse ];

  vendorHash = "sha256-Bmxe/vl1HfXSOm5qypDfAH35DIiS+1vnnZxCoQj+zNE=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/sirrobot01/decypharr/pkg/version.Version=${version}"
  ];

  meta = {
    description = "Media gateway for Debrid and Usenet";
    homepage = "https://github.com/sirrobot01/decypharr";
    license = lib.licenses.mit;
    mainProgram = "decypharr";
    platforms = lib.platforms.linux;
  };
}
