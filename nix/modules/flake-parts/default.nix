# flake-parts module: declare devices once under `tasmota`; get, per system,
#   packages.tasmota-deploy     (`nix run .#tasmota-deploy -- switch`)
#   checks.tasmota-validation   (offline settings check, run by `nix flake check`)
{
  config,
  lib,
  ...
}: let
  evalConfig = import ../../lib/eval-config.nix;
in {
  options.tasmota = lib.mkOption {
    type = lib.types.deferredModule;
    default = {};
    example = lib.literalExpression ''
      {
        decode-config.devices.kitchen = {
          source = "http://kitchen.lan";
          settings.friendlyname = [ "Kitchen" ];
        };
      }
    '';
    description = ''
      tasmota.nix configuration (the options of tasmota.nix's generic
      module).  It is system-independent and evaluated with each system's
      `pkgs`.
    '';
  };

  config.perSystem = {pkgs, ...}: let
    inherit
      ((evalConfig {
          inherit pkgs;
          modules = [config.tasmota];
        })
        .config)
      decode-config
      ;
  in
    lib.mkIf (decode-config.devices != {}) {
      packages.tasmota-deploy = decode-config.build.deployer;
      checks.tasmota-validation = decode-config.build.validation;
    };
}
