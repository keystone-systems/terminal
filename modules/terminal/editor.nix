{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keystone.terminal;
  helixPackage = pkgs.helix;
  previewMarkdown = pkgs.writeShellScriptBin "helix-preview-markdown" ''
    set -euo pipefail
    log="/tmp/helix-preview.log"
    temporary_file="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$temporary_file"' EXIT
    ${pkgs.coreutils}/bin/cat > "$temporary_file"

    echo "--- $(${pkgs.coreutils}/bin/date) ---" >> "$log"
    ${pkgs.pandoc}/bin/pandoc -f markdown "$temporary_file" -o /tmp/helix-preview.html 2>> "$log"
    url="file:///tmp/helix-preview.html"

    ${
      if pkgs.stdenv.isDarwin then
        ''
          printf '%s' "$url" | /usr/bin/pbcopy
          /usr/bin/open "$url" >> "$log" 2>&1 &
        ''
      else
        ''
          printf '%s' "$url" | ${pkgs.wl-clipboard}/bin/wl-copy
          ${pkgs.xdg-utils}/bin/xdg-open "$url" >> "$log" 2>&1 &
        ''
    }

    ${pkgs.coreutils}/bin/cat "$temporary_file"
  '';
in
{
  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      EDITOR = cfg.editor;
      VISUAL = cfg.editor;
    };

    # Dotfiles own Helix settings, languages, and theme adapters. Nix owns the
    # editor, language servers, formatters, and preview helper.
    home.packages =
      (with pkgs; [
        helixPackage
        bash-language-server
        docker-compose-language-service
        yaml-language-server
        dockerfile-language-server
        vscode-langservers-extracted
        helm-ls
        ruby-lsp
        solargraph
        prettier
        harper
        pandoc
        marksman
        zk
        xdg-utils
        previewMarkdown
      ])
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.wl-clipboard ];
  };
}
