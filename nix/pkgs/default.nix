# tasmota.nix packages, built with the given nixpkgs.
{pkgs}: let
  sources = pkgs.callPackage ./_sources/generated.nix {};
  decode-config = pkgs.callPackage (import ./decode-config {inherit sources;}) {};
  tasmota-deploy = pkgs.callPackage ./tasmota-deploy {inherit decode-config;};
in {
  inherit decode-config tasmota-deploy;
}
