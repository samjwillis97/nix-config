{
  lib,
  writers,
  python3,
  runCommand,
}:

let
  cli = writers.writePython3Bin "triage-state" { } ./triage_state.py;

  tests =
    runCommand "triage-state-tests"
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
  tests = tests;

  meta = {
    description = "Stable incident fingerprints and spawn budgets for triage threads";
    mainProgram = "triage-state";
    platforms = lib.platforms.unix;
  };
}
