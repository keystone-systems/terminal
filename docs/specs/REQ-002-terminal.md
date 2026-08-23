# REQ-002: Terminal Development Environment

## Ownership and composition

- **REQ-002.1** `ks.systems/terminal` MUST provide the canonical
  `keystone.terminal.*` Home Manager option surface.
- **REQ-002.2** `homeModules.default` MUST be file-backed. Repeated imports
  MUST NOT redeclare an option.
- **REQ-002.3** Nix MUST own packages, runtime services, accounts,
  credentials, executable adapters, and generated runtime fragments.
- **REQ-002.4** Stow MUST own editable terminal configuration.
- **REQ-002.5** The repository MUST provide user-agnostic starter templates.
- **REQ-002.6** The seed command MUST copy writable files. It MUST preserve an
  existing target unless the caller passes `--force`.
- **REQ-002.7** The manifest MUST describe the final relative path and
  executable mode of every starter file. A future immutable Home Manager mode
  MAY consume the same manifest. This requirement does not implement that
  mode.
- **REQ-002.8** The product MUST evaluate on x86-64 Linux, ARM64 Linux,
  x86-64 macOS, and ARM64 macOS. A Linux-only optional feature MUST have a
  platform guard.

## Theme contract

- **REQ-002.9** `keystone.terminal.theme.name` MUST select the default theme.
- **REQ-002.10** Every terminal theme MUST contain `zellij.kdl`,
  `helix.toml`, `btop.theme`, and `lazygit.yml`.
- **REQ-002.11** A switch MUST validate all terminal and extension-required
  paths before it changes `~/.config/themes/current`.
- **REQ-002.12** Activation MUST preserve a valid runtime selection. It MUST
  repair an absent, dangling, or stale terminal adapter.
- **REQ-002.13** The selector MUST update the Zellij, Helix, btop, and Lazygit
  adapters without a Nix rebuild.
- **REQ-002.14** A desktop product MAY append required paths and post-switch
  hooks. It MUST use the terminal selector.
- **REQ-002.15** The theme contract MUST work on a headless host.

Cohesive terminal-based development environment with modern tools, configured
through a single Home Manager flake output.

Key words: RFC 2119 (MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
MAY, REQUIRED, OPTIONAL).

## Functional Requirements

### FR-001: Shell Environment

The terminal environment MUST provide a modern, productive shell experience.

- The system MUST provide Zsh with completion and history management
- The system MUST provide directory navigation with fuzzy matching and frecency tracking
- The system MUST provide automatic environment loading for project-specific configurations
- The system MUST provide a unified prompt showing git status, execution time, and context
- The system MUST provide sensible aliases for common operations
- Plugin loading MUST NOT introduce perceptible startup lag

### FR-002: Text Editor

The terminal environment MUST include a modal text editor with language server support.

- The system MUST provide Helix as the default editor
- The editor MUST integrate language server protocol for common languages
- The editor MUST provide syntax highlighting and formatting
- The editor MUST provide modal editing with intuitive keybindings
- The editor MUST be set as `EDITOR` and `VISUAL` environment variables
- The editor MUST support theme configuration with sensible defaults

### FR-003: Terminal Multiplexer

The terminal environment MUST support session management and window splitting.

- The system MUST provide Zellij as the terminal multiplexer
- Tab and pane management MUST NOT conflict with other tool keybindings
- The multiplexer MUST support session persistence across disconnections
- The multiplexer MUST integrate with the shell environment
- The multiplexer SHOULD have minimal UI overhead for focus on content
- Keybindings MUST NOT conflict with Claude Code or other AI tools

### FR-004: Git Integration

The terminal environment MUST provide efficient git workflows.

- The system MUST provide Git CLI with sensible defaults and aliases
- Git LFS MUST be enabled by default
- The system MUST provide a terminal UI for git operations (lazygit)
- Automatic push remote setup MUST be enabled
- User identity (name, email) MUST be configurable
- Default branch MUST be set to "main"

### FR-005: File Navigation

The terminal environment MUST support efficient file browsing and searching.

- The system MUST provide a modern ls replacement with colors and git integration
- The system MUST provide fast recursive grep with regex support
- The system MUST provide a terminal file manager for visual navigation
- The system SHOULD provide CSV viewing for data inspection

### FR-006: AI Development Tools

The terminal environment MUST include AI-assisted development capabilities.

- The system MUST provide Claude Code CLI for AI-powered development
- The AI tools MUST integrate with the shell environment
- The system MUST support automatic installation and updates of AI tools
- AI tool keybindings MUST be compatible with the multiplexer

### FR-007: Language Server Support

The editor MUST support language servers for common development languages.

- The editor MUST provide language servers for Bash, Docker, YAML, JSON, HTML, CSS
- The editor MUST provide TypeScript/JavaScript support with prettier formatting
- The editor MUST provide Ruby support with multiple LSP backends
- The editor SHOULD provide Helm chart support for Kubernetes
- The editor MUST provide Markdown and prose linting with harper
- Automatic formatting on save MUST be supported for applicable languages

### FR-008: Configuration Interface

The module MUST expose a clear, documented configuration interface.

- A single `keystone.terminal.enable` option MUST activate all features
- Git user configuration (name, email) MUST be REQUIRED when git is enabled
- The default editor MUST be configurable
- Git integration MUST be independently toggleable
- Minimal configuration MUST be sufficient for a working setup

## Non-Functional Requirements

### NFR-001: Performance

- Shell startup time MUST be under 500ms
- Editor launch MUST complete in under 1 second
- Tab completion MUST respond in under 100ms
- Normal usage MUST NOT be blocked by background operations

### NFR-002: Consistency

- Keybindings MUST follow common conventions
- Colors and themes MUST be consistent across tools
- Configuration MUST merge without conflicts
- Updates MUST NOT break existing workflows

### NFR-003: Documentation

- All options MUST be documented with examples
- Configuration MUST be validated with assertions
- Error messages MUST provide remediation guidance
- Common use cases SHOULD be documented in CLAUDE.md

## Testing Requirements

### TR-001: VM Testing

- Test user with terminal environment enabled MUST be provisioned
- SSH access MUST be available for interactive validation
- All tools MUST be accessible in PATH
- Git configuration MUST be applied correctly
- Editor and LSPs MUST be functional

### TR-002: Integration Testing

- Home-manager activation MUST succeed
- Package installations MUST NOT conflict
- Service dependencies MUST be resolved correctly
- XDG configuration files MUST be created properly

## Success Criteria

### SC-001: Activation Success

- Fresh activation MUST complete without errors
- All programs MUST be available in PATH after login
- Shell MUST start with configured plugins loaded
- Editor MUST launch with LSPs running

### SC-002: Configuration Validation

- Missing required options MUST produce clear error messages
- Invalid git email MUST be detected during build
- Conflicting keybindings MUST be documented and resolved
- Option changes MUST apply without breaking existing sessions

### SC-003: User Experience

- New users MUST be able to configure in under 5 minutes
- Common development tasks MUST be supported out of the box
- Keybindings MUST be discoverable and documented
- Tools MUST work together without manual integration

## Out of Scope

- GUI terminal emulator configuration (Ghostty — separate module)
- Desktop integration (desktop-specific keybindings, notifications)
- Language-specific development environments (Node.js, Python, Rust toolchains — use direnv)
- Container tools (Docker, podman, kubectl — NixOS-level configuration)
- Database clients (psql, mysql, redis-cli — project-specific)
- Cloud provider CLIs (AWS, GCP, Azure — project-specific)
- Custom shell scripts (user-specific automation — home-manager configuration)
- SSH configuration (host definitions, keys — home-manager SSH module)
