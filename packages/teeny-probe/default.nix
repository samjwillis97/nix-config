{
  lib,
  writers,
}:

writers.writePython3Bin "teeny-probe" { } ./teeny-probe.py
// {
  meta = {
    description = "Read-only journald and systemd probe for teeny";
    mainProgram = "teeny-probe";
    platforms = lib.platforms.unix;
  };
}
