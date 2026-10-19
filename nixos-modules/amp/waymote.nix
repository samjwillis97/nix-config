{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wayland,
  libxkbcommon,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "waymote";
  version = "0.1.7";

  src = fetchurl {
    url = "https://github.com/rockorager/waymote/releases/download/v${finalAttrs.version}/waymote-server-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-7uQ59w8MPEfRwnkJdYpCcjphIgtPBra+ZyuExKCEa+c=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    wayland
    libxkbcommon
  ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp bin/waymote-gateway bin/waymote-streamd "$out/bin/"
    install -Dm644 LICENSE "$out/share/licenses/waymote/LICENSE"
    runHook postInstall
  '';

  meta = {
    description = "Wayland desktop streaming server for the Amp runner";
    homepage = "https://github.com/rockorager/waymote";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
