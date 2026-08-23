# Keystone Terminal — core terminal module entry point.
# Implements REQ-002 (Terminal Development Environment)
# See docs/specs/REQ-018-repo-management.md (development mode)
#
# All submodules are imported unconditionally. Each guards its own
# `home.packages`/`programs.*` with `config = mkIf cfg.enable {…}`, so a
# disabled submodule contributes zero runtime closure — only Nix module
# evaluation cost. A prior attempt gated the `imports` list on a
# `terminalMinimal` module argument; that proved fundamentally fragile
# because any sharedModules / agent-HM / nested-eval path that loaded the
# module without specialArgs hit an `_module.args` → `config` →
# `imports` → `_module.args` cycle. The right place to slim the live
# installer's surface is per-host configuration (enable flags), not
# import-list gating.
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal;
  notesPath = config.keystone.notes.path or "${config.home.homeDirectory}/notes";
  keystoneHome = "${config.home.homeDirectory}/.keystone";
  codeRoot = "${config.home.homeDirectory}/repos";
  worktreeRoot = "${codeRoot}/worktrees";
  ensurePathsScript = pkgs.writeShellScriptBin "keystone-ensure-paths" ''
    set -euo pipefail

    mkdir -p \
      "${keystoneHome}" \
      "${keystoneHome}/repos" \
      "${notesPath}" \
      "${codeRoot}" \
      "${worktreeRoot}"
  '';

  # Generate allowed_signers file content: "<email> <key>" per line
in
{
  imports = [
    ../shared/experimental.nix
    ../shared/repos.nix
    ../shared/update.nix
    ../shared/password-managers.nix
    ./shell.nix
    ./zide.nix
    ./editor.nix
    ./conventions.nix
    ./agents
    ./age-yubikey.nix
    ./devtools.nix
    ./mail.nix
    ./calendar.nix
    ./contacts.nix
    ./timer.nix
    ./tasks.nix
    ./agent-mail.nix
    ./sandbox.nix
    ./secrets.nix
    ./ssh-auto-load.nix
    ./forgejo.nix
    ./github-token-nix.nix
    ./grafana.nix
    ./theme.nix
  ];

  options.keystone.terminal = {
    enable = mkEnableOption "Keystone Terminal - Core terminal tools and configuration";

    devTools = mkOption {
      type = types.bool;
      default = false;
      description = "Enable additional development tools (csview)";
    };

    editor = mkOption {
      type = types.str;
      default = "hx";
      description = "Default editor command (e.g., 'hx' for helix, 'nvim' for neovim)";
    };

    git = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Validate the Git identity used by generated Keystone integrations";
      };

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Full name for git commits (required when git.enable is true)";
        example = "John Doe";
      };

      userEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Email address for git commits (required when git.enable is true)";
        example = "john@example.com";
      };

      sshPublicKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "SSH public keys for allowed_signers (git signature verification).";
      };

      signingKey = mkOption {
        type = types.str;
        default = "~/.ssh/id_ed25519";
        description = "SSH key for signing. Path or 'key::' prefix for inline public key.";
      };
    };

    ssh = {
      authSock = mkOption {
        type = types.str;
        default = "%t/ssh-agent";
        defaultText = literalExpression ''"%t/ssh-agent"'';
        description = "SSH agent socket exported to non-interactive services that need Git/SSH access.";
      };
    };

    integration.ksPackage = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Optional Keystone OS CLI package. The terminal product does not own this package.";
    };
  };

  config = mkIf cfg.enable {
    # Inherit development mode and repos from NixOS level if available (osConfig).
    # This ensures that setting keystone.development = true at the NixOS level
    # automatically applies to all users' terminal modules without manual bridging.
    keystone.development = mkIf (osConfig != null) (mkDefault (osConfig.keystone.development or false));
    keystone.repos = mkIf (osConfig != null) (mkDefault (osConfig.keystone.repos or { }));

    # Assertions to ensure required git options are set
    assertions = [
      {
        assertion = !cfg.git.enable || cfg.git.userName != null;
        message = "keystone.terminal.git.userName must be set when keystone.terminal.git.enable is true";
      }
      {
        assertion = !cfg.git.enable || cfg.git.userEmail != null;
        message = "keystone.terminal.git.userEmail must be set when keystone.terminal.git.enable is true";
      }
    ];

    # Nix owns tools. The seeded Git and Lazygit files remain editable in the
    # user's Stow repository, regardless of identity integration.
    home.packages = [
      pkgs.git
      pkgs.git-lfs
      pkgs.keystone-terminal.fetch-github-sources
      ensurePathsScript
    ];

    home.activation.keystoneEnsurePaths = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${ensurePathsScript}/bin/keystone-ensure-paths
    '';

    # Keystone Repo Sync Service — clones and pulls managed repositories.
    # Runs as a oneshot systemd user service during activation and on login.
    # Logs to journalctl -u keystone-repos-sync.service.
    systemd.user.services.keystone-repos-sync = mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Clone and update managed keystone repositories";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [ "GIT_TERMINAL_PROMPT=0" ];
        ExecStart = toString (
          pkgs.writeShellScript "keystone-repos-sync" ''
            set -euo pipefail
            mkdir_bin="${pkgs.coreutils}/bin/mkdir"
            dirname_bin="${pkgs.coreutils}/bin/dirname"
            timeout_bin="${pkgs.coreutils}/bin/timeout"
            git_bin="${pkgs.git}/bin/git"
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: repo: ''
                target="${keystoneHome}/repos/${name}"
                if [ ! -d "$target/.git" ]; then
                  echo "Cloning managed repo ${name} from ${repo.url}..."
                  "$mkdir_bin" -p "$("$dirname_bin" "$target")"
                  "$timeout_bin" --signal=TERM 15s \
                    "$git_bin" clone "${repo.url}" "$target" \
                    || echo "Warning: Failed to clone ${name} after 15s, skipping..."
                else
                  echo "Pulling managed repo ${name} at $target..."
                  "$timeout_bin" --signal=TERM 15s \
                    "$git_bin" -C "$target" pull --ff-only \
                    || echo "Warning: Failed to pull ${name} after 15s, skipping..."
                fi
              '') config.keystone.repos
            )}
          ''
        );
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    home.sessionVariables = {
      CODE_DIR = codeRoot;
      WORKTREE_DIR = worktreeRoot;
      NOTES_DIR = notesPath;
      # Interactive shells can override the system runtime channel pointer;
      # correctness no longer depends on this being present in detached apps.
      KS_UPDATE_CHANNEL = config.keystone.update.channel;
    };

  };
}
