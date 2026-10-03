{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.terminal.dotfiles;
  bootstrapTemplate = if cfg.bootstrap.template == null then "" else toString cfg.bootstrap.template;
  installer = pkgs.keystone-terminal.stow-dotfiles;
  templateRepo = pkgs.runCommand "keystone-dotfiles-bootstrap-source" { } ''
    mkdir -p "$out"
    ln -s ${lib.escapeShellArg bootstrapTemplate} "$out/packages"
  '';
  checkDotfiles = pkgs.writeShellApplication {
    name = "keystone-check-dotfiles";
    text = ''
      repo_path=${lib.escapeShellArg cfg.repoPath}
      source_args=(${
        lib.optionalString (cfg.source != null) "--source ${lib.escapeShellArg (toString cfg.source)}"
      })
      if [[ ! -e "$repo_path" && ! -L "$repo_path" ]]; then
        ${
          if cfg.bootstrap.enable then
            ''
              repo_path=${templateRepo}
              source_args=()
            ''
          else
            ''
              echo "dotfiles: $repo_path is missing and automatic bootstrap is disabled" >&2
              exit 1
            ''
        }
      fi
      exec ${installer}/bin/ks-stow-dotfiles --check \
        --repo "$repo_path" --target ${lib.escapeShellArg config.home.homeDirectory} \
        "''${source_args[@]}" ${lib.escapeShellArgs cfg.packages}
    '';
  };
  activateDotfiles = pkgs.writeShellApplication {
    name = "keystone-activate-dotfiles";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      repo_path=${lib.escapeShellArg cfg.repoPath}

      if [[ ! -e "$repo_path" && ! -L "$repo_path" ]]; then
        ${
          if cfg.bootstrap.enable then
            ''
              template_path=${lib.escapeShellArg bootstrapTemplate}
              parent_directory="$(dirname "$repo_path")"
              repo_name="$(basename "$repo_path")"
              mkdir -p "$parent_directory"
              staging="$(mktemp -d --tmpdir="$parent_directory" ".''${repo_name}.bootstrap.XXXXXX")"
              cleanup() {
                rm -rf -- "$staging"
              }
              trap cleanup EXIT

              mkdir "$staging/packages"
              cp -R "$template_path"/. "$staging/packages"/
              chmod -R u+w "$staging"
              git -C "$staging" init -b main
              mv --no-target-directory -- "$staging" "$repo_path"
              trap - EXIT
            ''
          else
            ''
              echo "dotfiles: $repo_path is missing and automatic bootstrap is disabled" >&2
              exit 1
            ''
        }
      elif [[ ! -d "$repo_path" ]]; then
        echo "dotfiles: $repo_path exists but is not a directory" >&2
        exit 1
      fi

      exec ${installer}/bin/ks-stow-dotfiles \
        --repo "$repo_path" --target ${lib.escapeShellArg config.home.homeDirectory} \
        ${lib.escapeShellArgs cfg.packages}
    '';
  };
in
{
  options.keystone.terminal.dotfiles = {
    enable = lib.mkEnableOption "activation of a mutable GNU Stow dotfiles checkout";

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/repos/${config.home.username}/dotfiles";
      defaultText = lib.literalExpression ''"${config.home.homeDirectory}/repos/${config.home.username}/dotfiles"'';
      description = "Path to the user-owned dotfiles checkout containing packages/.";
    };

    source = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional locked repository whose selected packages must match at deployment preflight. Activation uses the editable checkout.";
    };

    checkPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = checkDotfiles;
      description = "Read-only configured deployment preflight, providing bin/keystone-check-dotfiles.";
    };

    bootstrap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically create a missing dotfiles checkout from the pinned template.";
      };

      template = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.keystone-terminal.dotfile-templates;
        description = "Pinned template copied when automatic bootstrap creates the checkout.";
      };
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Stow packages to activate from the mutable checkout.";
    };
  };

  config = lib.mkMerge [
    {
      keystone.terminal.dotfiles.packages = lib.mkBefore [
        "bat"
        "btop"
        "git"
        "helix"
        "lazygit"
        "ssh"
        "themes"
        "zellij"
        "zsh"
      ];
    }
    (lib.mkIf (config.keystone.terminal.enable && cfg.enable) {
      home.packages = [
        pkgs.stow
        installer
      ];

      assertions = [
        {
          assertion = !cfg.bootstrap.enable || cfg.bootstrap.template != null;
          message = "keystone.terminal.dotfiles.bootstrap.template must be set when bootstrap is enabled";
        }
      ];

      home.activation.keystoneStowDotfiles = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        run ${activateDotfiles}/bin/keystone-activate-dotfiles
      '';
    })
  ];
}
