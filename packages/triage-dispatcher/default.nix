{
  lib,
  writers,
  python3,
  runCommand,
}:

let
  cli = writers.writePython3Bin "triage-dispatcher" { } ./dispatcher.py;

  tests =
    runCommand "triage-dispatcher-tests"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        cd ${./.}
        ${python3.interpreter} -m unittest discover -s . -p 'test_*.py'
        touch $out
      '';
in
cli
// {
  inherit tests;

  meta = {
    description = "Poll VictoriaLogs and dispatch Amp triage threads";
    mainProgram = "triage-dispatcher";
    platforms = lib.platforms.unix;
  };
}
