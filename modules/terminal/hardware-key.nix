{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.terminal.hardwareKey;
  identityPath = name: "${config.home.homeDirectory}/.ssh/id_ed25519_sk_${name}";
  scope = "user root host ${lib.concatStringsSep "," cfg.rootHosts}";
in
{
  options.keystone.terminal.hardwareKey = {
    enable = lib.mkEnableOption "portable YubiKey client tools";
    manageHandles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Deploy SSH handles; disable when the OS already owns them.";
    };
    rootHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hosts where root SSH uses only connected hardware keys.";
    };
    keys = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            serial = lib.mkOption { type = lib.types.strMatching "[0-9]+"; };
            publicKey = lib.mkOption { type = lib.types.str; };
            handleSource = lib.mkOption { type = lib.types.path; };
          };
        }
      );
      description = "Registered SSH handles and the serials used to select connected keys.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.openssh
      pkgs.yubikey-manager
      pkgs.yubico-piv-tool
    ];
    home.sessionPath = lib.mkIf pkgs.stdenv.isDarwin [ "${pkgs.openssh}/bin" ];
    assertions = [
      {
        assertion = builtins.all (name: builtins.match "[A-Za-z0-9_-]+" name != null) (
          builtins.attrNames cfg.keys
        );
        message = "Hardware key names MUST contain only letters, numbers, underscores, or hyphens.";
      }
    ];
    home.file = lib.mkIf cfg.manageHandles (
      lib.listToAttrs (
        lib.concatLists (
          lib.mapAttrsToList (name: key: [
            {
              name = ".ssh/id_ed25519_sk_${name}";
              value.source = key.handleSource;
            }
            {
              name = ".ssh/id_ed25519_sk_${name}.pub";
              value.text = key.publicKey + "\n";
            }
          ]) cfg.keys
        )
      )
    );
    # Included by the editable Stow SSH config; only this runtime fragment is Nix-owned.
    xdg.configFile."keystone/ssh/hardware-keys.conf" = lib.mkIf (cfg.rootHosts != [ ]) {
      text = ''
        Match ${scope}
          IdentitiesOnly yes
          IdentityAgent none
          IdentityFile none
      ''
      + lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: key: ''
          Match ${scope} exec "${pkgs.yubikey-manager}/bin/ykman list --serials 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Fxq -- ${key.serial}"
            IdentityFile ${identityPath name}
        '') cfg.keys
      )
      + "\nMatch all\n";
    };
  };
}
