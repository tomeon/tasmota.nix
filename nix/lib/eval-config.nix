# Evaluate tasmota.nix modules.  Works with or without flakes:
#
#   (import ./nix/lib/eval-config.nix {
#     pkgs = import <nixpkgs> {};
#     modules = [./devices.nix];
#   }).config.decode-config.build.deployer
#
# `modules` is a module or a list of modules.  Other arguments (`specialArgs`,
# `prefix`, ...) are passed to `lib.evalModules`; `class` is always "tasmota".
{
  pkgs,
  lib ? pkgs.lib,
  modules ? [],
  ...
} @ args:
lib.evalModules (removeAttrs args ["pkgs" "lib"]
  // {
    class = "tasmota";
    modules =
      [
        ../modules/tasmota
        {_module.args.pkgs = lib.mkDefault pkgs;}
      ]
      ++ lib.toList modules;
  })
