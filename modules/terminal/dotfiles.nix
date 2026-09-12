{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.terminal.dotfiles;
  packageDirectory = "${cfg.repoPath}/packages";
  bootstrapTemplate = if cfg.bootstrap.template == null then "" else toString cfg.bootstrap.template;
  activateDotfiles = pkgs.writeShellApplication {
    name = "keystone-activate-dotfiles";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.stow
    ];
    text = ''
      repo_path=${lib.escapeShellArg cfg.repoPath}
      package_directory=${lib.escapeShellArg packageDirectory}

      if [[ ! -e "$repo_path" ]]; then
        ${lib.optionalString (!cfg.bootstrap.enable) ''
          echo "dotfiles: $repo_path is missing and automatic bootstrap is disabled" >&2
          exit 1
        ''}

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
      elif [[ ! -d "$repo_path" ]]; then
        echo "dotfiles: $repo_path exists but is not a directory" >&2
        exit 1
      fi

      if [[ ! -d "$package_directory" ]]; then
        echo "dotfiles: $package_directory is missing" >&2
        exit 1
      fi

      for package in ${lib.escapeShellArgs cfg.packages}; do
        if [[ ! -d "$package_directory/$package" ]]; then
          echo "dotfiles: selected package $package is missing from $package_directory" >&2
          exit 1
        fi
      done

      stow \
        --dir "$package_directory" \
        --target ${lib.escapeShellArg config.home.homeDirectory} \
        --restow \
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
      home.packages = [ pkgs.stow ];

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
