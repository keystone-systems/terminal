# Changelog

## Unreleased

- Extract the Keystone terminal Home Manager product from `ks.systems/os`.
- Add Stow starter templates and non-destructive seeding.
- Add headless runtime theme switching for Zellij, Helix, btop, and Lazygit.
- Add `keystone.terminal.theme.renderHooks` for ordered, isolated generation
  rendering before theme activation.
- Promote successful theme generations to visible names and add a read-only
  `keystone-theme-switch --gc` candidate audit.
- Declare Linux and macOS evaluation outputs.
