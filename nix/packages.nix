# This flake's packages, as a `lib.makeScope` package set per system.  They are
# exposed as `packages.<system>.*` and, through flake-parts' `easyOverlay`, as
# `overlays.default` (built with the nixpkgs the overlay is applied to).
{lib, ...}: {
  perSystem = {
    config,
    pkgs,
    ...
  }: let
    scope = lib.makeScope pkgs.newScope (self: {
      sources = self.callPackage ./pkgs/_sources/generated.nix {};
      decode-config = self.callPackage ./pkgs/decode-config {};
      tasmota-deploy = self.callPackage ./pkgs/tasmota-deploy {};
    });
  in {
    packages = {
      inherit (scope) decode-config tasmota-deploy;
      default = config.packages.decode-config;
    };

    overlayAttrs = {
      inherit (config.packages) decode-config tasmota-deploy;
    };
  };
}
