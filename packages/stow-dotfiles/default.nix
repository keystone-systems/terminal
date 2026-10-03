{
  writeShellApplication,
  coreutils,
  diffutils,
  stow,
}:
writeShellApplication {
  name = "ks-stow-dotfiles";
  runtimeInputs = [
    coreutils
    diffutils
    stow
  ];
  text = builtins.readFile ./stow-dotfiles.sh;
}
