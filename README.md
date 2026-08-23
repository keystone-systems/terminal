# Keystone Terminal

Keystone Terminal is a standalone Home Manager product for Linux and macOS.
It installs terminal dependencies and generated runtime wiring. It also ships
starter files that a user copies into a Stow-managed dotfiles repository.

```nix
inputs.terminal.url = "git+ssh://forgejo@git.ncrmro.com:2222/ks.systems/terminal.git";
```

Import `terminal.homeModules.default`, apply `terminal.overlays.default`, and
set `keystone.terminal.enable = true`.

Seed editable defaults once:

```sh
nix run .#seed-dotfiles -- ~/repos/$USER/dotfiles/packages
```

The seed command MUST NOT overwrite an existing file unless the caller passes
`--force`. Nix MUST NOT own a seeded file after the copy.

## Layered themes

`keystone.terminal.theme.catalogs` is an ordered list of `{ name, path }`
catalogs. Later catalogs override files from earlier catalogs. Selection
materializes an immutable generation below
`$XDG_STATE_HOME/keystone/themes/generations/`, validates the composed theme,
and atomically switches `current`. The compatibility link
`$XDG_CONFIG_HOME/themes/current` always follows that state.

```sh
keystone-theme-switch                 # human-readable sorted list
keystone-theme-switch --list --json   # machine-readable list and current flag
keystone-theme-switch --refresh       # recompose the current selection
keystone-theme-switch tokyo-night
```

Every generation includes `.keystone-theme.json` with its theme name,
contributing catalogs, and selected background. A failing post-switch hook
MUST restore the previous generation and rerun its hook on a best-effort basis.
