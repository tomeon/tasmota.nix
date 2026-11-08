# Checks for the generic module, the flake-parts module, the overlay and the
# flake-compat entry point.  Package tests live in each package's
# passthru.tests.
{
  inputs,
  lib,
  pkgs,
  self,
  system,
  tasmota-deploy,
}: let
  configuration = args: self.lib.tasmotaConfiguration ({inherit system;} // args);

  eval = modules: (configuration {inherit modules;}).config;

  example = eval ./example.nix;

  # True if evaluating `expr` deeply throws (type errors, conflicts, failed
  # assertions).
  fails = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;

  # Evaluating the manifest file checks assertions.
  manifestFails = modules: fails (eval modules).build.manifestFile.drvPath;

  moduleResults = lib.runTests {
    testSourceDefaultsToName = {
      expr = (eval {fleet.devices.lamp = {};}).fleet.devices.lamp.source;
      expected = "lamp";
    };

    testDefaultsApplyToEveryDevice = {
      expr = lib.mapAttrs (_: d: d.settings.mqtt_host) example.fleet.devices;
      expected = {
        kitchen = "broker.lan";
        plug = "other.lan";
      };
    };

    testTagsFromDefaultsAndDevice = {
      expr = example.fleet.devices.kitchen.tags;
      expected = ["home" "lights"];
    };

    testListsDefinedTwiceAreAnError = {
      expr =
        fails
        (eval {
          fleet = {
            defaults.settings.friendlyname = ["a"];
            devices.x.settings.friendlyname = ["b"];
          };
        })
      .fleet
      .devices
      .x
      .settings;
      expected = true;
    };

    testDeviceOverridesMkDefault = {
      expr =
        (eval {
          fleet = {
            defaults.settings.friendlyname = lib.mkDefault ["a"];
            devices.x.settings.friendlyname = ["b"];
          };
        })
        .fleet
        .devices
        .x
        .settings
        .friendlyname;
      expected = ["b"];
    };

    testNestedSettingsMerge = {
      expr =
        (eval {
          fleet = {
            defaults.settings.flag.mqtt_enabled = 1;
            devices.x.settings.flag.save_state = 0;
          };
        })
        .fleet
        .devices
        .x
        .settings;
      expected.flag = {
        mqtt_enabled = 1;
        save_state = 0;
      };
    };

    testSettingsRejectNixPaths = {
      expr = fails (eval {fleet.devices.x.settings.ota_url = ./example.nix;}).fleet.devices.x.settings;
      expected = true;
    };

    testSecretAsNixPathIsRejected = {
      expr = manifestFails {fleet.devices.x.settings.sta_pwd = [{_secret = ./example.nix;}];};
      expected = true;
    };

    testRelativeSecretIsRejected = {
      expr = manifestFails {fleet.devices.x.settings.sta_pwd = [{_secret = "secrets/wifi";}];};
      expected = true;
    };

    testSecretWithOtherAttributesIsRejected = {
      expr = manifestFails {
        fleet.devices.x.settings.sta_pwd = [
          {
            _secret = "/run/secrets/wifi";
            extra = 1;
          }
        ];
      };
      expected = true;
    };

    testPasswordFileAsNixPathIsRejected = {
      expr = fails (eval {fleet.devices.x.passwordFile = ./example.nix;}).fleet.devices.x.passwordFile;
      expected = true;
    };

    testRelativePasswordFileIsRejected = {
      expr = fails (eval {fleet.devices.x.passwordFile = "secrets/web";}).fleet.devices.x.passwordFile;
      expected = true;
    };

    testEmptyTagIsRejected = {
      expr = fails (eval {fleet.devices.x.tags = [""];}).fleet.devices.x.tags;
      expected = true;
    };

    testCredentialsInSourceWarn = {
      expr = (eval {fleet.devices.x.source = "HTTP://admin:pw@x.lan";}).warnings;
      expected = ["fleet.devices.x.source contains a password, which ends up in the Nix store; use passwordFile instead."];
    };

    testEvalModulesArgumentsPassThrough = {
      expr =
        (configuration {
          modules = {fleet.devices.lamp = {};};
          prefix = ["tasmota"];
        })
        .config
        .fleet
        .devices
        .lamp
        .source;
      expected = "lamp";
    };

    testManifest = {
      expr = {
        inherit (example.build.manifest) version;
        devices = lib.attrNames example.build.manifest.devices;
      };
      expected = {
        version = 1;
        devices = ["kitchen" "plug"];
      };
    };

    testNoDevices = {
      expr = (eval {}).build.validation ? drvPath;
      expected = true;
    };
  };

  # A flake using the flake-parts module, evaluated on the spot.
  testInputs = {
    inherit (inputs) nixpkgs;
    self = {
      outPath = ./.;
      inputs = testInputs;
    };
  };

  evalFlake = module:
    (inputs.flake-parts.lib.evalFlakeModule {
        inputs = testInputs;
        moduleLocation = "${toString ./.}/default.nix#test-flake";
      } {
        imports = [self.flakeModules.default module];
        systems = [system];
        tasmota.configurations.example = ./example.nix;
      }).config.flake;

  flake = evalFlake {};

  flakePartsResults = lib.runTests {
    testConfigurationIsEvaluated = {
      expr = flake.legacyPackages.${system}.tasmotaConfigurations.example.config.fleet.devices.kitchen.settings.hostname;
      expected = "kitchen";
    };

    testPackageAndCheckPerConfiguration = {
      expr = {
        packages = lib.attrNames flake.packages.${system};
        checks = lib.attrNames flake.checks.${system};
      };
      expected = {
        packages = ["tasmota-deploy-example"];
        checks = ["tasmota-example"];
      };
    };

    testPackagesCanBeLeftOut = {
      expr = (evalFlake {tasmota.flakePackages = false;}).packages.${system} or {};
      expected = {};
    };

    testChecksCanBeLeftOut = {
      expr = (evalFlake {tasmota.flakeCheck = false;}).checks.${system} or {};
      expected = {};
    };
  };

  assertNoFailures = name: results:
    lib.throwIfNot (results == []) "${name}: ${builtins.toJSON results}" true;

  sameDrv = a: b: a.drvPath == b.drvPath;
in {
  module-eval = assert assertNoFailures "module tests" moduleResults;
    pkgs.emptyFile;

  module-manifest =
    pkgs.runCommand "tasmota-module-manifest" {
      nativeBuildInputs = [pkgs.jq];
      manifest = example.build.manifestFile;
    } ''
      check() {
        jq -e "$1" "$manifest" >/dev/null || { echo "failed: $1" >&2; exit 1; }
      }
      check '.version == 1'
      check '.decodeConfig | test("/bin/decode-config.py$")'
      check '.blankDump | test("tasmota-blank-ESP82.dmp$")'
      check '.keySchema | test("tasmota-key-schema.json$")'
      check '.devices | keys == ["kitchen", "plug"]'
      check '.devices.kitchen == {
        source: "http://kitchen.lan",
        passwordFile: "/run/secrets/tasmota-web",
        tags: ["home", "lights"],
        settings: {hostname: "kitchen", mqtt_host: "broker.lan", sta_pwd: [{_secret: "/run/secrets/wifi"}]},
        extraArgs: [],
        validate: true
      }'
      check '.devices.plug.source == "plug" and .devices.plug.passwordFile == null'
      check '.devices.plug.extraArgs == ["--username", "admin"]'
      test -x "$(jq -r .decodeConfig "$manifest")"
      touch "$out"
    '';

  # The module's manifest and deployer, end to end against mock devices.
  module-integration = tasmota-deploy.runTests {
    name = "tasmota-module-integration";
    args = "test_integration.Integration.test_nix_manifest";
    env.NIX_MANIFEST = example.build.manifestFile;
  };

  module-validation = example.build.validation;

  flake-parts-module = assert assertNoFailures "flake-parts module tests" flakePartsResults;
    pkgs.runCommand "tasmota-flake-parts-module" {
      deployer = flake.packages.${system}.tasmota-deploy-example;
      validation = flake.checks.${system}.tasmota-example;
    } ''
      test -x "$deployer/bin/tasmota-deploy"
      test -e "$validation"
      touch "$out"
    '';

  # flake-compat, as `default.nix` uses it, exposes the same outputs to Nix
  # without flakes.  (`src = self` rather than `default.nix`'s `./.`, which
  # flake-compat would copy again in pure evaluation.)
  flake-compat = let
    compat = (import inputs.flake-compat {src = self;}).defaultNix;
    compatExample = compat.lib.tasmotaConfiguration {
      inherit system;
      modules = ./example.nix;
    };
  in
    assert sameDrv compat.packages.${system}.tasmota-deploy tasmota-deploy;
    assert sameDrv compatExample.config.build.validation example.build.validation;
    assert lib.attrNames compat.flakeModules == lib.attrNames self.flakeModules;
      pkgs.emptyFile;

  # The overlay builds the packages with the nixpkgs it is applied to.
  overlay = assert sameDrv (pkgs.extend self.overlays.default).tasmota-deploy tasmota-deploy;
    pkgs.emptyFile;
}
