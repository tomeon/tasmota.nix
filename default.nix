# Entry point for Nix without flakes: this flake's outputs, via flake-compat.
#
#   let
#     tasmota-nix = import (builtins.fetchTarball "https://github.com/tomeon/tasmota.nix/archive/main.tar.gz");
#   in
#     (tasmota-nix.lib.tasmotaConfiguration {modules = [./tasmota.nix];}).config.build.deployer
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  inherit (lock.nodes.${lock.nodes.root.inputs.flake-compat}) locked;
  flake-compat = builtins.fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
    sha256 = locked.narHash;
  };
in
  (import flake-compat {src = ./.;}).defaultNix
