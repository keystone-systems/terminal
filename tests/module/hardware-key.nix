{ pkgs, home-manager, ... }:
let
  homeDirectory = if pkgs.stdenv.isDarwin then "/Users/key-test" else "/home/key-test";
  fakeYkman = pkgs.writeShellScriptBin "ykman" ''
    printf '%s\n' "''${YUBI_TEST_SERIAL:-}"
  '';
  hm = home-manager.lib.homeManagerConfiguration {
    pkgs = pkgs.extend (_: _: { yubikey-manager = fakeYkman; });
    modules = [
      ../../modules/terminal/hardware-key.nix
      ../../modules/terminal/age-yubikey.nix
      {
        home.username = "key-test";
        home.homeDirectory = homeDirectory;
        home.stateVersion = "25.05";
        keystone.terminal.ageYubikey = {
          enable = true;
          identities = [
            {
              serial = "123";
              identity = "AGE-PLUGIN-YUBIKEY-TEST";
            }
          ];
        };
        keystone.terminal.hardwareKey = {
          enable = true;
          rootHosts = [ "fleet.example" ];
          keys = {
            black = {
              serial = "123";
              publicKey = "test-black";
              handleSource = pkgs.writeText "black-handle" "test";
            };
            green = {
              serial = "456";
              publicKey = "test-green";
              handleSource = pkgs.writeText "green-handle" "test";
            };
          };
        };
      }
    ];
  };
  cfg = hm.config;
  sshConfig =
    pkgs.writeText "hardware-key-ssh.conf"
      cfg.xdg.configFile."keystone/ssh/hardware-keys.conf".text;
in
assert cfg.home.sessionVariables.SOPS_AGE_KEY_FILE == cfg.keystone.terminal.ageYubikey.identityPath;
assert builtins.hasAttr ".ssh/id_ed25519_sk_black" cfg.home.file;
assert !pkgs.stdenv.isDarwin || builtins.elem "${pkgs.openssh}/bin" cfg.home.sessionPath;
pkgs.runCommand "terminal-hardware-key"
  {
    nativeBuildInputs = [
      pkgs.openssh
      pkgs.gnugrep
    ];
  }
  ''
    export SHELL=${pkgs.runtimeShell}
    export YUBI_TEST_SERIAL=123
    ssh -F ${sshConfig} -G root@fleet.example > black
    grep -Fx 'identityagent none' black
    grep -Fx 'identitiesonly yes' black
    grep -Fx 'securitykeyprovider internal' black
    grep -Fx 'identityfile ${homeDirectory}/.ssh/id_ed25519_sk_black' black
    ! grep -q 'id_ed25519_sk_green' black
    export YUBI_TEST_SERIAL=456
    ssh -F ${sshConfig} -G root@fleet.example > green
    grep -Fx 'identityfile ${homeDirectory}/.ssh/id_ed25519_sk_green' green
    ! grep -q 'id_ed25519_sk_black' green
    unset YUBI_TEST_SERIAL
    ssh -F ${sshConfig} -G root@fleet.example > absent
    ! grep -q 'id_ed25519_sk_' absent
    ssh -F ${sshConfig} -G git@github.com > normal
    ! grep -q 'id_ed25519_sk_' normal
    touch "$out"
  ''
