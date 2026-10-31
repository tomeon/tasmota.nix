{moduleWithSystem}:
moduleWithSystem ({} @ perSystem: {
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.programs.decode-config;
in {
  options = {
    sources = mkOption {
      description = "Tasmota sources and associated options.";
      default = {};
      type = types.submodule (sources: {
        options = {
          defaults = mkOption {
            type = types.deferredModule;
            default = {};
            description = ''
              Configuration applied to all entries in `sources.sources`.
            '';
          };

          sources = mkOption {
            default = {};
            type = types.attrsOf (types.submodule ({name, ...}: {
              imports = [sources.defaults];

              options = {
                source = mkOption {
                  type = types.nonEmptyStr;
                  default = name;
                  description = ''
                    Filename, host name, or URL identifying the source.
                  '';
                };

                package = mkOption {
                  type = types.package;
                  default = perSystem.config.packages.decode-config;
                  description = ''
                    Package providing decode-config.
                  '';
                };

                extraArgs = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = ''
                  '';
                };
              };
            }));
          };
        };
      });
    };
  };

  config =
    lib.mkIf cfg.enable {
    };
})
