# The generic tasmota.nix module: `fleet.*` (devices and their settings),
# `packages.*` (the tools used) and `build.*` (manifest, deployer, offline
# validation).
#
# Evaluate it with this flake's `lib.tasmotaConfiguration`, its flake-parts
# module, or `lib.evalModules` with `class = "tasmota"` and a `system` (or
# `pkgs`) module argument: `build.nix` takes its packages from this flake's
# `perSystem` through `moduleWithSystem`.
{moduleWithSystem}: {
  imports = [
    ./fleet.nix
    (import ./build.nix {inherit moduleWithSystem;})
  ];
}
