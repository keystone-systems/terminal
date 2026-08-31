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
materializes a self-contained, generation-scoped theme below
`$XDG_STATE_HOME/keystone/themes/generations/`, validates the composed theme,
and atomically switches `current`. The compatibility link
`$XDG_CONFIG_HOME/themes/current` always follows that state. Catalogs MUST NOT
provide `.keystone-theme.json`; the selector reserves that path for generation
metadata.

```sh
keystone-theme-switch                 # human-readable sorted list
keystone-theme-switch --list --json   # machine-readable list and current flag
keystone-theme-switch --backgrounds --json # wallpapers in the current composed theme
keystone-theme-switch --background backgrounds/2-example.jpg
keystone-theme-switch --refresh       # recompose the current selection
keystone-theme-switch --gc            # audit non-current generation candidates
keystone-theme-switch tokyo-night
```

Every generation includes `.keystone-theme.json` with its theme name,
contributing catalogs, and selected background. Selecting a wallpaper changes
only that metadata and runs the same post-switch hook as a theme change. A
failing post-switch hook MUST restore the previous state and rerun its hook on
a best-effort basis. If the first activation fails, the selector removes the
new `current` link and its adapter links. A valid current generation remains the
rollback anchor even when its catalog theme has disappeared. Post-switch hooks
receive empty standard input from `/dev/null` so they cannot consume the
configured hook list. The selector validates every configured post-switch hook
executable before moving `current`.

Render hooks receive the selected theme name and a private staged generation
after catalog composition. Copied catalog files are owner-writable so renderers
can replace them without changing the source catalogs. They run sequentially in
configured `renderHooks` order, receive empty standard input from `/dev/null`,
and have their standard output forwarded to standard error as diagnostics.
Renderers MUST NOT create the selector-reserved `.keystone-theme.json` metadata
path or leave any symbolic link or multiply linked file in the staged
generation. The selector checks these boundaries after each renderer and before
starting the next one.
Validation and activation happen only after every renderer succeeds; a failure
removes the staged generation and preserves the active generation.

Successful activation promotes the hidden staging directory to a visible
generation. The selector retains successful generations and does not prune them
automatically; it removes every failed staged or activation generation. A
refresh or reconciliation whose composed content is identical to the current
generation, excluding selector metadata, keeps the current generation instead
of retaining a duplicate.
`keystone-theme-switch --gc` is a read-only audit that deterministically lists
visible, non-current candidate paths without changing the filesystem. Hidden
in-flight staging directories and visible generations paired with a
well-formed reservation whose writer PID still accepts signal 0 are never
candidates. Malformed, unreadable, and otherwise unknown reservations also
remain excluded conservatively. A valid reservation whose writer PID is
provably dead does not hide its visible, non-current generation. With no current
selection, all other visible generations are candidates; with a dangling
`current`, the audit refuses to guess and fails. It cannot prove that an
external consumer no longer references a candidate. After verifying that a
listed path is unreferenced, an operator MAY remove that exact path and its
paired dead-writer reservation manually. Removal remains an explicit operation:

```sh
keystone-theme-switch --gc
candidate=/exact/verified/generation-candidate
rm -rf -- "$candidate"
rm -f -- "$(dirname "$candidate")/.${candidate##*/}.reserve"
```
