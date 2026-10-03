{
  pkgs,
  home-manager,
  self,
}:
let
  template = pkgs.runCommand "dotfiles-bootstrap-test-template" { } ''
    mkdir -p "$out/test/.config"
    echo template > "$out/test/.config/example"
  '';
  mkHome =
    bootstrap:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.default
        {
          home.username = "dotfiles-test";
          home.homeDirectory = "/build/dotfiles-test";
          home.stateVersion = "24.11";
          keystone.terminal = {
            enable = true;
            ai.enable = false;
            git.enable = false;
            sandbox.enable = false;
            dotfiles = {
              enable = true;
              repoPath = "/build/dotfiles-test/repo";
              packages = pkgs.lib.mkForce [ "test" ];
              bootstrap.enable = bootstrap;
              bootstrap.template = if bootstrap then template else null;
            };
          };
        }
      ];
    };
  home = mkHome true;
  noBootstrap = mkHome false;
  check = "${home.config.keystone.terminal.dotfiles.checkPackage}/bin/keystone-check-dotfiles";
in
pkgs.runCommand "terminal-dotfiles-bootstrap" { nativeBuildInputs = [ pkgs.git ]; } ''
  export HOME=/build/dotfiles-test
  mkdir -p "$HOME/.config"
  run() { "$@"; }
  if ${noBootstrap.config.keystone.terminal.dotfiles.checkPackage}/bin/keystone-check-dotfiles; then
    echo 'disabled bootstrap preflight accepted missing repo' >&2; exit 1
  fi
  if ( ${noBootstrap.config.home.activation.keystoneStowDotfiles.data} ); then
    echo 'disabled bootstrap activation accepted missing repo' >&2; exit 1
  fi
  test ! -e "$HOME/repo"
  echo conflict > "$HOME/.config/example"
  if ${check}; then echo 'bootstrap check accepted conflict' >&2; exit 1; fi
  test ! -e "$HOME/repo"
  test "$(cat "$HOME/.config/example")" = conflict
  rm "$HOME/.config/example"
  ${check}
  test ! -e "$HOME/repo"
  run() { "$@"; }
  ${home.config.home.activation.keystoneStowDotfiles.data}
  test -d "$HOME/repo/.git"
  test -L "$HOME/.config/example"
  echo edited > "$HOME/.config/example"
  ${home.config.home.activation.keystoneStowDotfiles.data}
  test "$(cat "$HOME/.config/example")" = edited
  ${check}
  touch "$out"
''
