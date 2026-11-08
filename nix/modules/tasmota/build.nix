# The `packages` and `build` namespaces: the tools used, the manifest that
# `tasmota-deploy` reads, the deployer with that manifest built in, and an
# offline validation.  Package defaults, and the nixpkgs these outputs are
# built with, come from this flake's `perSystem` through `moduleWithSystem`.
{moduleWithSystem}: {
  _file = ./build.nix;

  imports = [
    (moduleWithSystem (
      perSystem @ {
        config,
        pkgs,
      }: {
        config,
        lib,
        ...
      }: let
        inherit (lib) literalExpression mkOption types;
        cfg = config.build;
        inherit (config.packages) decode-config tasmota-deploy;
      in {
        # `assertions` and `warnings`, as in NixOS.
        imports = [lib.genericModules.assertions];

        options = {
          packages = {
            decode-config = mkOption {
              type = types.package;
              default = perSystem.config.packages.decode-config;
              defaultText = literalExpression "decode-config from tasmota.nix";
              description = ''
                decode-config package.  It must provide `mkBlankDump` and
                `keySchema` in `passthru`, as tasmota.nix's package does.
              '';
            };

            tasmota-deploy = mkOption {
              type = types.package;
              default = perSystem.config.packages.tasmota-deploy;
              defaultText = literalExpression "tasmota-deploy from tasmota.nix";
              description = "tasmota-deploy package wrapped by {option}`build.deployer`.";
            };
          };

          build = {
            manifest = mkOption {
              type = types.lazyAttrsOf types.raw;
              default = {};
              description = ''
                The JSON document that `tasmota-deploy` reads.  Evaluating it
                checks `assertions` and prints `warnings`.
              '';
              apply = manifest:
                lib.asserts.checkAssertWarn config.assertions config.warnings
                ({version = 1;} // manifest);
            };

            manifestFile = mkOption {
              type = types.package;
              readOnly = true;
              description = "{option}`build.manifest` as a JSON file.";
            };

            validation = mkOption {
              type = types.package;
              readOnly = true;
              description = ''
                Derivation that checks every device's settings offline
                (`tasmota-deploy build`); suitable for `checks`.
              '';
            };

            deployer = mkOption {
              type = types.package;
              readOnly = true;
              description = "`tasmota-deploy` with this configuration's manifest built in.";
            };
          };
        };

        config.build = {
          manifest = {
            decodeConfig = lib.getExe decode-config;
            blankDump = decode-config.mkBlankDump {};
            inherit (decode-config) keySchema;
          };

          manifestFile = pkgs.writeText "tasmota-manifest.json" (builtins.toJSON cfg.manifest);

          validation = pkgs.runCommand "tasmota-validation" {} ''
            ${lib.getExe cfg.deployer} build
            touch "$out"
          '';

          deployer =
            pkgs.runCommand "tasmota-deploy" {
              nativeBuildInputs = [pkgs.makeWrapper];
              meta.mainProgram = "tasmota-deploy";
            } ''
              makeWrapper ${lib.getExe tasmota-deploy} "$out/bin/tasmota-deploy" \
                --add-flags "--manifest ${cfg.manifestFile}"
            '';
        };
      }
    ))
  ];
}
