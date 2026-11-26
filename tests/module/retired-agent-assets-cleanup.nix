{ pkgs }:
let
  cleanup = pkgs.writeShellScript "cleanup-retired-agent-assets" (
    builtins.readFile ../../modules/terminal/agents/cleanup-retired-agent-assets.sh
  );
in
pkgs.runCommand "test-retired-agent-assets-cleanup"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    bash ${../retired-agent-assets-cleanup.sh} ${cleanup}
    touch "$out"
  ''
