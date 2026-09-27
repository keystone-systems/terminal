# Hardware-key clients

`keystone.terminal.hardwareKey.enable` installs OpenSSH with its internal
FIDO2 provider, YubiKey Manager, and the PIV tools on Linux and macOS. macOS
sessions prefer this SSH client through `home.sessionPath`.

Declare `keys.<name>.serial`, `publicKey`, and `handleSource` to deploy
existing SSH key handles. Set `manageHandles = false` when the OS module
already owns those files. Signing material MUST remain on the physical key.

For root connections, `rootHosts` generates
`~/.config/keystone/ssh/hardware-keys.conf`. The editable Stow SSH config
MUST include `~/.config/keystone/ssh/*.conf` before its host blocks. New
starter checkouts include this line; existing dotfiles need the same explicit
addition. Nix MUST NOT replace the editable SSH config.

The generated policy uses only connected keys, selected by serial number,
and disables agent and software-key fallback for the configured root hosts.
Other destinations and usernames retain their usual identity selection.

`keystone.terminal.ageYubikey` writes the configured plugin identities and
exports both `AGE_IDENTITIES_FILE` and `SOPS_AGE_KEY_FILE`. It installs sops,
ssh-to-age, age-plugin-yubikey, and YubiKey Manager independently of OS
services. Secret editing and recipient updates use the existing sops workflow;
no agenix dependency or separate secrets repository is required.

On NixOS, the OS owns pcscd, udev access, and inbound root authorization.
On macOS, the native smart-card stack supplies device access.
