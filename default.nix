# Entry point without flakes:
#
#   let
#     tasmota = import (fetchTarball "https://github.com/tomeon/tasmota.nix/archive/main.tar.gz") {};
#   in
#     (tasmota.evalConfig {modules = [./devices.nix];}).config.decode-config.build.deployer
#
# `pkgs` defaults to the nixpkgs revision pinned in flake.lock.
{
  pkgs ? let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    nixpkgs = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  in
    import (fetchTarball {
      url = "https://github.com/${nixpkgs.owner}/${nixpkgs.repo}/archive/${nixpkgs.rev}.tar.gz";
      sha256 = nixpkgs.narHash;
    }) {},
}: let
  packages = import ./nix/pkgs {inherit pkgs;};
in
  packages
  // {
    modules = {
      tasmota = {
        default = ./nix/modules/tasmota;
        decode-config = ./nix/modules/tasmota/decode-config.nix;
      };
      flake.default = ./nix/modules/flake-parts;
    };

    evalConfig = {
      modules ? [],
      specialArgs ? {},
    }:
      import ./nix/lib/eval-config.nix {inherit pkgs modules specialArgs;};
  }
