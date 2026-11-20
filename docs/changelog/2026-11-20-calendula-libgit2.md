# Provide system libraries for the Pimalaya tools

Provide libgit2 when building Calendula, Cardamum, and Comodoro with
Nixpkgs' system-library Rust hooks. Provide SQLite for Calendula and
Cardamum and include it in their executable search paths. Cargo build
and install hooks can load the corresponding libraries on Linux.

Built Calendula, Cardamum, and Comodoro with the workstation Nixpkgs pin
and ran each version command without LD_LIBRARY_PATH. Terminal flake
checks passed for the native build and all-system evaluation.
