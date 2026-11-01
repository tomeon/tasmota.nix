# Checks for the modules and the entry points.  Package tests live in each
# package's passthru.tests.
{
  pkgs,
  flake-parts,
  self,
  nixpkgs,
}: let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;
  packages = import ../pkgs {inherit pkgs;};

  eval = modules:
    (import ../lib/eval-config.nix {
      inherit pkgs;
      modules = lib.toList modules;
    })
    .config
    .decode-config;

  example = eval ./example.nix;

  # True if evaluating `expr` deeply throws (type errors, conflicts, asserts).
  fails = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;

  moduleResults = lib.runTests {
    testSourceDefaultsToName = {
      expr = (eval {decode-config.devices.lamp = {};}).devices.lamp.source;
      expected = "lamp";
    };

    testDefaultsApplyToEveryDevice = {
      expr = lib.mapAttrs (_: d: d.settings.mqtt_host) example.devices;
      expected = {
        kitchen = "broker.lan";
        plug = "other.lan";
      };
    };

    testTagsFromDefaultsAndDevice = {
      expr = example.devices.kitchen.tags;
      expected = ["home" "lights"];
    };

    testConflictingListsAreAnError = {
      expr =
        fails
        (eval {
          decode-config = {
            defaults.settings.friendlyname = ["a"];
            devices.x.settings.friendlyname = ["b"];
          };
        })
      .devices
      .x
      .settings;
      expected = true;
    };

    testDeviceOverridesMkDefault = {
      expr =
        (eval {
          decode-config = {
            defaults.settings.friendlyname = lib.mkDefault ["a"];
            devices.x.settings.friendlyname = ["b"];
          };
        })
        .devices
        .x
        .settings
        .friendlyname;
      expected = ["b"];
    };

    testNestedSettingsMerge = {
      expr =
        (eval {
          decode-config = {
            defaults.settings.flag.mqtt_enabled = 1;
            devices.x.settings.flag.save_state = 0;
          };
        })
        .devices
        .x
        .settings;
      expected.flag = {
        mqtt_enabled = 1;
        save_state = 0;
      };
    };

    testSecretAsNixPathIsRejected = {
      expr =
        fails
        (eval {
          decode-config.devices.x.settings.sta_pwd = [{_secret = ./example.nix;}];
        })
      .build
      .manifest
      .drvPath;
      expected = true;
    };

    testPasswordFileAsNixPathIsRejected = {
      expr = fails (eval {decode-config.devices.x.passwordFile = ./example.nix;}).devices.x.passwordFile;
      expected = true;
    };

    testNoDevices = {
      expr = (eval {}).build.validation ? drvPath;
      expected = true;
    };
  };

  flake = devices:
    flake-parts.lib.mkFlake {inputs = {inherit self nixpkgs;};} {
      imports = [../modules/flake-parts];
      systems = [system];
      tasmota = devices;
    };

  nonFlake = import ../../default.nix {inherit pkgs;};
in {
  module-eval =
    if moduleResults == []
    then pkgs.runCommand "tasmota-module-eval" {} "touch $out"
    else throw "module tests failed: ${builtins.toJSON moduleResults}";

  module-manifest =
    pkgs.runCommand "tasmota-module-manifest" {
      nativeBuildInputs = [pkgs.jq];
      manifest = example.build.manifest;
    } ''
      check() {
        jq -e "$1" "$manifest" >/dev/null || { echo "failed: $1" >&2; exit 1; }
      }
      check '.version == 1'
      check '.decodeConfig | test("/bin/decode-config.py$")'
      check '.blankDump | test("tasmota-blank-ESP82.dmp$")'
      check '.devices | keys == ["kitchen", "plug"]'
      check '.devices.kitchen == {
        source: "http://kitchen.lan",
        passwordFile: "web",
        tags: ["home", "lights"],
        settings: {hostname: "kitchen", mqtt_host: "broker.lan", sta_pwd: [{_secret: "wifi"}]},
        extraArgs: [],
        validate: true
      }'
      check '.devices.plug.source == "plug" and .devices.plug.passwordFile == null'
      check '.devices.plug.extraArgs == ["--json-indent", "2"]'
      test -x "$(jq -r .decodeConfig "$manifest")"
      touch "$out"
    '';

  # The module's manifest and deployer, end to end against mock devices.
  module-integration = packages.tasmota-deploy.runTests {
    name = "tasmota-module-integration";
    args = "test_integration.Integration.test_nix_manifest";
    env.NIX_MANIFEST = example.build.manifest;
  };

  module-validation = example.build.validation;

  flake-parts-module = let
    withDevices = flake ./example.nix;
    without = flake {};
  in
    pkgs.runCommand "tasmota-flake-parts-module" {} ''
      test -x ${lib.getExe withDevices.packages.${system}.tasmota-deploy}
      test -e ${withDevices.checks.${system}.tasmota-validation}
      ${lib.optionalString (without.packages.${system} or {} ? tasmota-deploy) ''
        echo "tasmota-deploy should not be defined without devices" >&2
        exit 1
      ''}
      touch "$out"
    '';

  non-flake-entry = pkgs.runCommand "tasmota-non-flake-entry" {} ''
    test -x ${lib.getExe nonFlake.decode-config}
    test -x ${lib.getExe nonFlake.tasmota-deploy}
    test -e ${(nonFlake.evalConfig {modules = [./example.nix];}).config.decode-config.build.validation}
    test -e ${nonFlake.modules.flake.default}/default.nix
    touch "$out"
  '';
}
