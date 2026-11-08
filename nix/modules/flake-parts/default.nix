# flake-parts module: tasmota.nix configurations as flake outputs.
#
#   tasmota.configurations.home = ./tasmota.nix;
#
# evaluates, for each system, into
# `legacyPackages.<system>.tasmotaConfigurations.home`.  Unless switched off,
# it also adds `packages.<system>.tasmota-deploy-home` (the deployer with that
# configuration built in: `nix run .#tasmota-deploy-home -- switch`) and
# `checks.<system>.tasmota-home` (offline validation).
{tasmotaLib}: {
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.tasmota;
in {
  options.tasmota = {
    configurations = mkOption {
      type = types.lazyAttrsOf types.deferredModule;
      default = {};
      example = lib.literalExpression ''
        {
          home = {
            imports = [./tasmota];
            fleet.devices.kitchen.settings.friendlyname = ["Kitchen"];
          };
        }
      '';
      description = ''
        tasmota.nix configurations: modules for the generic module, each
        evaluated for every system into
        `legacyPackages.<system>.tasmotaConfigurations.<name>`.
      '';
    };

    flakePackages = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to add `packages.<system>.tasmota-deploy-<name>`, the
        deployer with the configuration built in, for each of
        {option}`tasmota.configurations`.
      '';
    };

    flakeCheck = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to add `checks.<system>.tasmota-<name>`, which validates the
        configuration's settings offline, for each of
        {option}`tasmota.configurations`.
      '';
    };
  };

  config.perSystem = {system, ...}: let
    configurations = lib.mapAttrs (_: module:
      tasmotaLib.tasmotaConfiguration {
        inherit system;
        modules = [module];
      })
    cfg.configurations;

    outputs = prefix: attr:
      lib.mapAttrs' (name: configuration:
        lib.nameValuePair "${prefix}${name}" configuration.config.build.${attr})
      configurations;
  in {
    legacyPackages.tasmotaConfigurations = configurations;
    packages = lib.mkIf cfg.flakePackages (outputs "tasmota-deploy-" "deployer");
    checks = lib.mkIf cfg.flakeCheck (outputs "tasmota-" "validation");
  };
}
