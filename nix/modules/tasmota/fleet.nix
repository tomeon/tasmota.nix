# The `fleet` namespace: the devices to deploy and the settings to deploy.
{
  config,
  lib,
  ...
}: let
  inherit (lib) literalExpression mkOption types;

  cfg = config.fleet;

  # A secret's location: an absolute path given as a string, so that the file
  # is never copied into the world-readable Nix store.
  externalFile = types.pathWith {
    absolute = true;
    inStore = false;
  };

  # Any JSON value.  Unlike `pkgs.formats.json`, paths are rejected (turning
  # one into JSON would copy the file into the Nix store), and a list defined
  # in two places is an error rather than concatenated, since Tasmota arrays
  # are positional.
  jsonValue =
    types.nullOr (types.oneOf [
      types.bool
      types.int
      types.float
      types.str
      (types.attrsOf jsonValue)
      (types.uniq (types.listOf jsonValue))
    ])
    // {description = "JSON value";};

  # Every `{ _secret = ...; }` placeholder in a value, as `{ path; value; }`.
  findSecrets = path: value:
    if lib.isAttrs value
    then
      if value ? _secret
      then [{inherit path value;}]
      else lib.concatLists (lib.mapAttrsToList (k: findSecrets (path ++ [k])) value)
    else if lib.isList value
    then lib.concatLists (lib.imap0 (i: findSecrets (path ++ [(toString i)])) value)
    else [];

  credentialsInUrl = source: builtins.match "[a-zA-Z][a-zA-Z0-9+.-]*://[^/@]*:[^/@]*@.*" source != null;

  where = name: "fleet.devices.${lib.strings.escapeNixIdentifier name}";

  deviceAssertions = name: device:
    map (s: {
      assertion = lib.attrNames s.value == ["_secret"] && externalFile.check s.value._secret;
      message = "${where name}.settings.${lib.concatStringsSep "." s.path}: a secret must be written `{ _secret = \"/absolute/path\"; }`, with a string outside the Nix store.";
    })
    (findSecrets [] device.settings);

  deviceModule = {name, ...}: {
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
        type = types.nullOr externalFile;
        default = null;
        example = "/run/secrets/tasmota-web";
        description = ''
          File holding the device's web password (HTTP sources) or the MQTT
          broker password (MQTT sources), read when deploying, not when
          building.  An absolute path given as a string, so that the file is
          not copied into the Nix store.
        '';
      };

      tags = mkOption {
        type = types.listOf types.nonEmptyStr;
        default = [];
        example = ["lights" "upstairs"];
        description = ''
          Tags for selecting devices, as in `tasmota-deploy switch --on @lights`.
        '';
      };

      settings = mkOption {
        type = types.attrsOf jsonValue;
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

          An attribute set `{ _secret = "/absolute/path"; }` is replaced with
          the contents of that file (minus trailing newlines) when deploying,
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
          Whether to check {option}`settings` at build time: keys against
          every hardware platform's layout, values against a blank ESP8266
          configuration, both in decode-config's newest layout.  Disable this
          for a device on older firmware that uses settings no longer present.
          Keys and values are always checked against the device itself before
          anything is uploaded.
        '';
      };
    };
  };
in {
  options.fleet = {
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
        A module applied to every device in {option}`fleet.devices`.
        Definitions here have normal priority: use `lib.mkDefault` for values
        that individual devices may override.
      '';
    };

    devices = mkOption {
      type = types.attrsOf (types.submodule [deviceModule cfg.defaults]);
      default = {};
      description = "Tasmota devices, keyed by a name of your choosing.";
    };
  };

  config = {
    assertions = lib.concatLists (lib.mapAttrsToList deviceAssertions cfg.devices);

    warnings =
      lib.concatLists
      (lib.mapAttrsToList (name: device:
        lib.optional (credentialsInUrl device.source)
        "${where name}.source contains a password, which ends up in the Nix store; use passwordFile instead.")
      cfg.devices);

    build.manifest.devices =
      lib.mapAttrs (_: device: {
        inherit (device) source passwordFile tags settings extraArgs validate;
      })
      cfg.devices;
  };
}
