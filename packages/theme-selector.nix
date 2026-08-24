{
  writeShellApplication,
  coreutils,
  findutils,
  gnugrep,
  jq,
}:

writeShellApplication {
  name = "keystone-theme-selector";
  runtimeInputs = [
    coreutils
    findutils
    gnugrep
    jq
  ];
  text = builtins.readFile ../modules/terminal/theme-selector.sh;
}
