# ks.systems/terminal — Editing Guide

This repository owns the standalone Keystone terminal product for Linux and
macOS.

Nix MUST own packages, services, accounts, credentials, executable adapters,
generated runtime fragments, and theme selection. Stow MUST own editable
shell, editor, multiplexer, monitor, Git, SSH, and theme files.

`templates/` is a user-agnostic starter set. Home Manager MUST atomically
bootstrap a missing checkout, initialize it as a local Git repository, and
stow the selected packages. It MUST NOT seed or overwrite an existing
checkout. Nix MUST NOT link an editable file from the store. The explicit
`seed-dotfiles` maintenance command MUST preserve an existing file unless the
caller passes `--force`.

Every theme MUST provide `zellij.kdl`, `helix.toml`, `btop.theme`, and
`lazygit.yml`. Desktop products MAY append required paths and post-switch
hooks. They MUST NOT replace the terminal selector or redeclare
`keystone.terminal.theme.name`.

The public module is `homeModules.default`. Keep it file-backed so repeated
imports deduplicate. The overlay namespace is `pkgs.keystone-terminal`.

Run:

```sh
nix flake check --all-systems --no-build
nix flake check
```
