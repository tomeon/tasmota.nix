# Declarative Tasmota device configuration, applied with decode-config.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) literalExpression mkOption types;
  cfg = config.decode-config;
  packages = import ../../pkgs {inherit pkgs;};

  # `toJSON` would copy a Nix path into the world-readable store.
  checkSecrets = loc: value:
    if builtins.isAttrs value
    then
      if value ? _secret && builtins.isPath value._secret
      then
        throw ''
          ${loc}._secret is a Nix path, which would copy the secret into the Nix store.
          Use a string instead, e.g. "/run/secrets/wifi".''
      else lib.all lib.id (lib.mapAttrsToList (k: checkSecrets "${loc}.${k}") value)
    else if builtins.isList value
    then lib.all (checkSecrets loc) value
    else true;

  credentialsInUrl = source: builtins.match "[a-z]+://[^/@]*:[^/@]*@.*" source != null;

  deviceModule = {name, ...}: {
    imports = [cfg.defaults];

    options = {
      source = mkOption {
        type = types.nonEmptyStr;
        default = name;
        example = "mqtts://user@broker.lan/tasmota_kitchen";
        description = ''
          Where decode-config reads and writes this device's configuration
          (its `--source`): a host name, an `http(s)://` or `mqtt(s)://` URL,
          or a configuration dump file.  Do not put a password here; it would
          end up in the Nix store.  Use {option}`passwordFile`.
        '';
      };

      passwordFile = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        example = "/run/secrets/tasmota-web";
        description = ''
          File holding the device's web password (HTTP sources) or the MQTT
          broker password (MQTT sources).  It is read when deploying, not
          when building; relative paths are resolved against the directory
          `tasmota-deploy` runs in.  Give a string, not a Nix path, so the
          file is not copied into the Nix store.
        '';
      };

      tags = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["lights" "upstairs"];
        description = ''
          Tags for selecting devices, as in `tasmota-deploy switch --on @lights`.
        '';
      };

      settings = mkOption {
        # Unlike `types.json`, `anything` refuses to merge differing lists
        # rather than concatenating them; Tasmota arrays are positional.
        type = types.attrsOf types.anything;
        default = {};
        example = literalExpression ''
          {
            friendlyname = [ "Kitchen" ];
            mqtt_host = "broker.lan";
            sta_pwd = [ { _secret = "/run/secrets/wifi"; } ];
          }
        '';
        description = ''
          Partial decode-config JSON for this device.  Only the keys given
          here are written; all other settings on the device are kept.
          A shorter list sets only the first elements of a Tasmota array.

          Run `tasmota-deploy pull` to see the keys a device has.

          An attribute set `{ _secret = "/path"; }` is replaced with the
          contents of that file (minus trailing newlines) when deploying,
          following the nixpkgs `genJqSecretsReplacementSnippet` convention.
        '';
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["--fulltopic" "%prefix%/%topic%/"];
        description = ''
          Extra arguments for every decode-config call for this device,
          e.g. MQTT TLS options.
        '';
      };

      validate = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to check {option}`settings` at build time against a blank
          configuration in decode-config's newest layout.  Disable this for
          a device on older firmware that uses settings no longer present.
        '';
      };
    };
  };

  manifest = {
    version = 1;
    decodeConfig = lib.getExe cfg.package;
    blankDump = cfg.package.mkBlankDump {};
    devices =
      lib.mapAttrs (
        name: device:
          assert checkSecrets "decode-config.devices.${name}.settings" device.settings;
            lib.warnIf (credentialsInUrl device.source)
            "decode-config.devices.${name}.source contains a password, which ends up in the Nix store; use passwordFile instead."
            {
              inherit (device) source passwordFile tags settings extraArgs validate;
            }
      )
      cfg.devices;
  };
in {
  options.decode-config = {
    package = mkOption {
      type = types.package;
      default = packages.decode-config;
      defaultText = literalExpression "decode-config from tasmota.nix";
      description = ''
        decode-config package.  It must provide `mkBlankDump` in `passthru`,
        as tasmota.nix's package does.
      '';
    };

    deployPackage = mkOption {
      type = types.package;
      default = packages.tasmota-deploy;
      defaultText = literalExpression "tasmota-deploy from tasmota.nix";
      description = "tasmota-deploy package wrapped by {option}`decode-config.build.deployer`.";
    };

    defaults = mkOption {
      type = types.deferredModule;
      default = {};
      example = literalExpression ''
        {
          tags = [ "home" ];
          settings.mqtt_host = lib.mkDefault "broker.lan";
        }
      '';
      description = ''
        Module applied to every entry of {option}`decode-config.devices`.
      '';
    };

    devices = mkOption {
      type = types.attrsOf (types.submodule deviceModule);
      default = {};
      description = "Tasmota devices, by name.";
    };

    build = {
      manifest = mkOption {
        type = types.package;
        readOnly = true;
        description = "JSON manifest describing the devices, read by tasmota-deploy.";
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

  config.decode-config.build = {
    manifest = pkgs.writeText "tasmota-manifest.json" (builtins.toJSON manifest);

    validation = pkgs.runCommand "tasmota-validation" {} ''
      ${lib.getExe cfg.build.deployer} build
      touch "$out"
    '';

    deployer =
      pkgs.runCommand "tasmota-deploy" {
        nativeBuildInputs = [pkgs.makeWrapper];
        meta.mainProgram = "tasmota-deploy";
      } ''
        makeWrapper ${lib.getExe cfg.deployPackage} "$out/bin/tasmota-deploy" \
          --add-flags "--manifest ${cfg.build.manifest}"
      '';
  };
}
