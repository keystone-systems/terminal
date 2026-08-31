{
  writeShellApplication,
  coreutils,
  diffutils,
  findutils,
  gnugrep,
  jq,
}:

writeShellApplication {
  name = "keystone-theme-selector";
  runtimeInputs = [
    coreutils
    diffutils
    findutils
    gnugrep
    jq
  ];
  text = builtins.readFile ../modules/terminal/theme-selector.sh;
}
