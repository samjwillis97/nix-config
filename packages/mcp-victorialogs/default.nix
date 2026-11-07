{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "mcp-victorialogs";
  version = "1.9.0";

  src = fetchFromGitHub {
    owner = "VictoriaMetrics";
    repo = "mcp-victorialogs";
    rev = "v${version}";
    hash = "sha256-esfd6Eg1j2BCgee1T5tiIdSPWVEBqhI4UGDKRFYyn3s=";
  };

  # The upstream repository vendors its Go dependencies. The web UI is only
  # used for the landing page in HTTP mode; the MCP endpoint does not need it.
  vendorHash = null;

  env.CGO_ENABLED = "0";

  subPackages = [ "cmd/mcp-victorialogs" ];

  preBuild = ''
    mkdir -p web/dist
    cat > web/dist/index.html <<'EOF'
    <!doctype html>
    <meta charset="utf-8">
    <title>VictoriaLogs MCP</title>
    <p>This server exposes the VictoriaLogs MCP endpoint at <code>/mcp</code>.</p>
    EOF
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.date=unknown"
  ];

  meta = {
    description = "Read-only Model Context Protocol server for VictoriaLogs";
    homepage = "https://github.com/VictoriaMetrics/mcp-victorialogs";
    license = lib.licenses.asl20;
    mainProgram = "mcp-victorialogs";
    platforms = lib.platforms.unix;
  };
}
