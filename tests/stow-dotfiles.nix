{ pkgs }:
pkgs.runCommand "stow-dotfiles"
  {
    nativeBuildInputs = [
      pkgs.keystone-terminal.stow-dotfiles
      pkgs.coreutils
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    echo --adopt > "$HOME/.stowrc"
    echo --adopt > .stowrc
    mkdir -p "$HOME/.local/share/containers/unreadable" repo/packages/test/.config
    chmod 000 "$HOME/.local/share/containers/unreadable"
    printf 'managed\n' > repo/packages/test/.config/example
    repo="$PWD/repo"
    ks-stow-dotfiles --repo "$repo" --target "$HOME" --check test
    test ! -e "$HOME/.config"
    mkdir -p "$HOME/.config"
    printf 'user content\n' > "$HOME/.config/example"
    if ks-stow-dotfiles --repo "$repo" --target "$HOME" --check test; then
      echo 'preflight accepted conflict' >&2; exit 1
    fi
    if ks-stow-dotfiles --repo "$repo" --target "$HOME" test; then
      echo 'activation accepted conflict' >&2; exit 1
    fi
    test "$(cat "$HOME/.config/example")" = 'user content'
    rm "$HOME/.config/example"
    mkdir -p repo/packages/unselected/.config
    ln -s "$repo/packages/unselected/.config/removed" "$HOME/.config/unrelated-stale"
    ks-stow-dotfiles --repo "$repo" --target "$HOME" test
    test -L "$HOME/.config/unrelated-stale"
    test "$(readlink "$HOME/.config/unrelated-stale")" = "$repo/packages/unselected/.config/removed"
    test -L "$HOME/.config/example"
    test ! -L "$HOME/.config"
    printf 'edited\n' > repo/packages/test/.config/example
    ks-stow-dotfiles --repo "$repo" --target "$HOME" test
    test "$(cat "$HOME/.config/example")" = edited
    cp -R repo locked
    ks-stow-dotfiles --repo "$repo" --target "$HOME" --check --source "$PWD/locked" test
    printf 'changed\n' > repo/packages/test/.config/example
    if ks-stow-dotfiles --repo "$repo" --target "$HOME" --check --source "$PWD/locked" test; then
      echo 'preflight accepted source mismatch' >&2; exit 1
    fi
    chmod 700 "$HOME/.local/share/containers/unreadable"
    touch "$out"
  ''
