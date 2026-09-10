{
  lib,
  buildGoModule,
  makeWrapper,
  git,
  openssh,
  tmux,
  fzf,
  direnv,
}:

buildGoModule {
  pname = "f";
  version = "0.1.0";
  src = ./.;
  subPackages = [ "." ];
  env.CGO_ENABLED = "0";
  vendorHash = "sha256-CN/C1saBKQ1sjIC0/Gw9o9DRZGwwfVD1M6mjvWDktv8=";
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];
  checkPhase = ''
    go test ./...
  '';
  postInstall = ''
    wrapProgram "$out/bin/f" \
      --prefix PATH : "${
        lib.makeBinPath [
          git
          openssh
          tmux
          fzf
          direnv
        ]
      }"
  '';
}
