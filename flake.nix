{
  description = "Standalone Keystone Home Manager terminal environment and Stow starter templates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/61b7c44c4073f0b827768aff0049561b5110ea5a";
    nixpkgs-x86-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane/756d6d07c3818ea95d1e2cdac63fa7d02fe3e61b";
    himalaya = {
      url = "github:pimalaya/himalaya";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    calendula = {
      url = "github:pimalaya/calendula";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cardamum = {
      url = "github:pimalaya/cardamum";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    comodoro = {
      url = "github:pimalaya/comodoro/b70b3605acc358e0d9cb57525adba9c05fc53f3d";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    grafana-mcp-src = {
      url = "github:grafana/mcp-grafana";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-x86-darwin,
      home-manager,
      crane,
      himalaya,
      calendula,
      cardamum,
      comodoro,
      llm-agents,
      grafana-mcp-src,
      ...
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      nixpkgsFor = system: if system == "x86_64-darwin" then nixpkgs-x86-darwin else nixpkgs;
      themeDirectory = builtins.readDir ./templates/themes/.config/themes;
      themeNames = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") themeDirectory);
      manifestFrom =
        root:
        map (file: {
          path = lib.removePrefix "${toString root}/" (toString file);
          executable = lib.hasInfix "/.local/bin/" (toString file);
        }) (lib.filesystem.listFilesRecursive root);
      manifest = manifestFrom ./templates;
    in
    {
      homeModules.default = ./modules/default.nix;

      overlays.default = import ./overlays/default.nix {
        inherit
          self
          crane
          himalaya
          calendula
          cardamum
          comodoro
          llm-agents
          grafana-mcp-src
          ;
      };

      lib = {
        dotfiles.manifest = manifest;
        dotfiles.manifestFrom = manifestFrom;
        inherit themeNames;
        templatesPath = ./templates;
        sharedModules = {
          experimental = ./modules/shared/experimental.nix;
          repos = ./modules/shared/repos.nix;
          update = ./modules/shared/update.nix;
          password-managers = ./modules/shared/password-managers.nix;
          system-flake = ./modules/shared/system-flake.nix;
          dev-script-link = ./modules/shared/dev-script-link.nix;
        };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import (nixpkgsFor system) {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          dotfileTemplates = pkgs.runCommand "keystone-terminal-dotfile-templates" { } ''
            cp -r ${./templates}/. $out
          '';
        in
        {
          dotfile-templates = dotfileTemplates;
          seed-dotfiles = pkgs.writeShellApplication {
            name = "seed-dotfiles";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
            ];
            text = ''
              usage() {
                echo "Usage: seed-dotfiles [--force] <dotfiles-packages-dir>" >&2
              }

              force=0
              target=""
              for arg in "$@"; do
                case "$arg" in
                  --force) force=1 ;;
                  -h|--help) usage; exit 0 ;;
                  *) target="$arg" ;;
                esac
              done
              if [ -z "$target" ]; then usage; exit 2; fi

              mkdir -p "$target"
              cd ${dotfileTemplates}
              find . -type f -print0 | while IFS= read -r -d "" source; do
                relative="''${source#./}"
                destination="$target/$relative"
                if [ -e "$destination" ] && [ "$force" -ne 1 ]; then
                  echo "skip (exists): $relative"
                  continue
                fi
                mode=0644
                if [ -x "$source" ]; then mode=0755; fi
                install -D -m "$mode" "$source" "$destination"
                echo "seeded: $relative"
              done
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import (nixpkgsFor system) {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          home = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeModules.default
              {
                home.username = "terminal-test";
                home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/terminal-test" else "/home/terminal-test";
                home.stateVersion = "24.11";
                keystone.terminal = {
                  enable = true;
                  ai.enable = false;
                  git.enable = false;
                  sandbox.enable = false;
                };
              }
            ];
          };
          selector = pkgs.keystone-terminal.theme-selector;
          wrapperRenderHook = pkgs.writeShellApplication {
            name = "keystone-theme-render";
            text = ''
              printf '%s\n' "$1" > "$2/wrapper-rendered"
            '';
          };
          wrapperCatalog = pkgs.runCommand "terminal-theme-wrapper-catalog" { } ''
            mkdir -p "$out"
            cp -R ${./templates/themes/.config/themes}/tokyo-night "$out/"
          '';
          wrapperHomeDirectory = "/build/terminal-theme-wrapper";
          wrapperHome = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeModules.default
              {
                home.username = "theme-wrapper-test";
                home.homeDirectory = wrapperHomeDirectory;
                home.stateVersion = "24.11";
                keystone.terminal = {
                  enable = true;
                  ai.enable = false;
                  git.enable = false;
                  sandbox.enable = false;
                  theme = {
                    catalogs = [
                      {
                        name = "wrapper";
                        path = wrapperCatalog;
                      }
                    ];
                    renderHooks = [ wrapperRenderHook ];
                    requiredPaths = [ "wrapper-rendered" ];
                  };
                };
              }
            ];
          };
          themeSwitch = lib.findFirst (
            package: lib.getName package == "keystone-theme-switch"
          ) (throw "keystone-theme-switch is missing from home.packages") wrapperHome.config.home.packages;
          themeActivation = pkgs.writeText "terminal-theme-activation" (
            wrapperHome.config.home.activation.keystoneTerminalTheme.data
          );
        in
        {
          theme-contract = pkgs.runCommand "terminal-theme-contract" { } ''
            for theme in ${lib.concatStringsSep " " themeNames}; do
              root=${./templates/themes/.config/themes}/"$theme"
              for path in ${
                lib.concatStringsSep " " (
                  home.config.keystone.terminal.theme.requiredPaths
                  ++ map (adapter: adapter.source) home.config.keystone.terminal.theme.adapters
                )
              }; do
                [ "$path" = . ] && continue
                test -s "$root/$path" || { echo "$theme lacks $path" >&2; exit 1; }
              done
            done
            touch $out
          '';
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          theme-selector =
            assert wrapperHome.config.home.homeDirectory == wrapperHomeDirectory;
            import ./tests/theme-selector.nix {
              inherit
                pkgs
                selector
                themeSwitch
                themeActivation
                wrapperHomeDirectory
                ;
              inherit (home.config.keystone.terminal.theme) adapters requiredPaths;
              configHome = home.config.xdg.configHome;
            };
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          home-standalone = home.activationPackage;
          terminal-zide = import ./tests/module/terminal-zide.nix {
            inherit
              pkgs
              lib
              self
              home-manager
              ;
          };
          terminal-mail = import ./tests/module/terminal-mail.nix {
            inherit pkgs self home-manager;
          };
          retired-agent-assets-cleanup = import ./tests/module/retired-agent-assets-cleanup.nix {
            inherit pkgs;
          };
        }
      );

      formatter = forAllSystems (system: (nixpkgsFor system).legacyPackages.${system}.nixfmt);
    };
}
