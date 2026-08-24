{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.keystone.terminal;
  themeCfg = cfg.theme;
  requiredPaths = lib.concatStringsSep ":" themeCfg.requiredPaths;
  adapters = lib.concatMapStringsSep "\n" (
    adapter: "${adapter.source}\t${adapter.target}"
  ) themeCfg.adapters;
  catalogs = lib.concatMapStringsSep "\n" (
    catalog: "${catalog.name}\t${toString catalog.path}"
  ) themeCfg.catalogs;
  hooks = lib.concatStringsSep "\n" (map toString themeCfg.postSwitchHooks);
  selector = pkgs.keystone-terminal.theme-selector;
  switch = pkgs.writeShellApplication {
    name = "keystone-theme-switch";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      export KEYSTONE_STATE_HOME="${config.xdg.stateHome}"
      export KEYSTONE_THEME_CATALOGS="${catalogs}"
      export KEYSTONE_THEME_REQUIRED_PATHS="${requiredPaths}"
      export KEYSTONE_THEME_ADAPTERS="${adapters}"
      export KEYSTONE_THEME_HOOKS="${hooks}"

      case "$#:$*" in
        "0:")
          echo "Available themes:"
          ${selector}/bin/keystone-theme-selector list-json \
            | jq -r '.themes[] | "  \(.name)" + (if .current then " *" else "" end)'
          ;;
        "2:--list --json") ${selector}/bin/keystone-theme-selector list-json ;;
        "1:--current") ${selector}/bin/keystone-theme-selector current ;;
        "1:--refresh") ${selector}/bin/keystone-theme-selector refresh ;;
        1:*)
          ${selector}/bin/keystone-theme-selector select "$1"
          echo "Switched to theme: $1"
          ;;
        *) echo "Usage: keystone-theme-switch [--list --json|--current|--refresh|<theme-name>]" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  options.keystone.terminal.theme = {
    name = mkOption {
      type = types.str;
      default = "tokyo-night";
      description = "Default theme. Activation preserves another valid runtime selection.";
    };
    requiredPaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Validation-only paths that every selectable theme MUST provide.";
    };
    adapters = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            source = mkOption { type = types.str; };
            target = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
      description = "Theme-generation sources and the adapter links that consume them.";
    };
    catalogs = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption { type = types.str; };
            path = mkOption { type = types.path; };
          };
        }
      );
      default = [
        {
          name = "terminal";
          path = ../../templates/themes/.config/themes;
        }
      ];
      description = "Ordered low-to-high-precedence theme catalogs.";
    };
    postSwitchHooks = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Packages that provide bin/keystone-theme-hook.";
    };
  };

  config = mkIf cfg.enable {
    keystone.terminal.theme.adapters = lib.mkBefore [
      {
        source = "zellij.kdl";
        target = "${config.xdg.configHome}/zellij/themes/current.kdl";
      }
      {
        source = "helix.toml";
        target = "${config.xdg.configHome}/helix/themes/current.toml";
      }
      {
        source = "btop.theme";
        target = "${config.xdg.configHome}/btop/themes/current.theme";
      }
      {
        source = "lazygit.yml";
        target = "${config.xdg.configHome}/keystone/lazygit/current.yml";
      }
      {
        source = ".";
        target = "${config.xdg.configHome}/themes/current";
      }
    ];
    home.packages = [ switch ];
    home.sessionVariables.LG_CONFIG_FILE = "${config.xdg.configHome}/lazygit/config.yml,${config.xdg.configHome}/keystone/lazygit/current.yml";
    home.activation.keystoneTerminalTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      KEYSTONE_STATE_HOME="${config.xdg.stateHome}" \
        KEYSTONE_THEME_CATALOGS="${catalogs}" \
        KEYSTONE_THEME_REQUIRED_PATHS="${requiredPaths}" \
        KEYSTONE_THEME_ADAPTERS="${adapters}" \
        KEYSTONE_THEME_HOOKS="${hooks}" \
        ${selector}/bin/keystone-theme-selector reconcile "${themeCfg.name}"
    '';
  };
}
