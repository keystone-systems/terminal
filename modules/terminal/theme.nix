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
  catalogs = lib.concatMapStringsSep "\n" (
    catalog: "${catalog.name}\t${toString catalog.path}"
  ) themeCfg.catalogs;
  hooks = lib.concatStringsSep "\n" (map toString themeCfg.postSwitchHooks);
  selector = pkgs.writeShellApplication {
    name = "keystone-theme-selector";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = builtins.readFile ./theme-selector.sh;
  };
  switch = pkgs.writeShellApplication {
    name = "keystone-theme-switch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "Available themes:"
        KEYSTONE_CONFIG_HOME="${config.xdg.configHome}" KEYSTONE_STATE_HOME="${config.xdg.stateHome}" \
          KEYSTONE_THEME_CATALOGS="${catalogs}" ${selector}/bin/keystone-theme-selector list-json \
          | ${pkgs.jq}/bin/jq -r '.themes[] | "  \(.name)" + (if .current then " *" else "" end)'
        exit 0
      fi
      if [ "$#" -eq 2 ] && [ "$1" = "--list" ] && [ "$2" = "--json" ]; then
        KEYSTONE_CONFIG_HOME="${config.xdg.configHome}" KEYSTONE_STATE_HOME="${config.xdg.stateHome}" \
          KEYSTONE_THEME_CATALOGS="${catalogs}" ${selector}/bin/keystone-theme-selector list-json
        exit 0
      fi
      if [ "$#" -eq 1 ] && [ "$1" = "--refresh" ]; then
        KEYSTONE_CONFIG_HOME="${config.xdg.configHome}" KEYSTONE_STATE_HOME="${config.xdg.stateHome}" \
          KEYSTONE_THEME_CATALOGS="${catalogs}" KEYSTONE_THEME_REQUIRED_PATHS="${requiredPaths}" \
          KEYSTONE_THEME_HOOKS="${hooks}" ${selector}/bin/keystone-theme-selector refresh
        exit 0
      fi
      if [ "$#" -ne 1 ]; then
        echo "Usage: keystone-theme-switch <theme-name>" >&2
        exit 2
      fi
      theme="$1"
      KEYSTONE_CONFIG_HOME="${config.xdg.configHome}" \
        KEYSTONE_STATE_HOME="${config.xdg.stateHome}" \
        KEYSTONE_THEME_CATALOGS="${catalogs}" \
        KEYSTONE_THEME_REQUIRED_PATHS="${requiredPaths}" \
        KEYSTONE_THEME_HOOKS="${hooks}" \
        ${selector}/bin/keystone-theme-selector select "$theme"
      echo "Switched to theme: $theme"
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
      default = [
        "zellij.kdl"
        "helix.toml"
        "btop.theme"
        "lazygit.yml"
      ];
      description = "Files that every selectable theme MUST provide.";
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
    home.packages = [ switch ];
    home.sessionVariables.LG_CONFIG_FILE = "${config.xdg.configHome}/lazygit/config.yml,${config.xdg.configHome}/keystone/lazygit/current.yml";
    home.activation.keystoneTerminalTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      KEYSTONE_CONFIG_HOME="${config.xdg.configHome}" \
        KEYSTONE_STATE_HOME="${config.xdg.stateHome}" \
        KEYSTONE_THEME_CATALOGS="${catalogs}" \
        KEYSTONE_THEME_REQUIRED_PATHS="${requiredPaths}" \
        KEYSTONE_THEME_HOOKS="${hooks}" \
        ${selector}/bin/keystone-theme-selector reconcile "${themeCfg.name}"
    '';
  };
}
