# Evaluate tasmota.nix modules.  Works with or without flakes:
#
#   (import ./nix/lib/eval-config.nix {
#     pkgs = import <nixpkgs> {};
#     modules = [./devices.nix];
#   }).config.decode-config.build.deployer
{
  pkgs,
  lib ? pkgs.lib,
  modules ? [],
  specialArgs ? {},
}:
lib.evalModules {
  class = "tasmota";
  inherit specialArgs;
  modules =
    [
      ../modules/tasmota
      {_module.args.pkgs = lib.mkDefault pkgs;}
    ]
    ++ modules;
}
