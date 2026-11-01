{
  lib,
  python3,
  runCommand,
  stdenvNoCC,
  decode-config,
}: let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./tasmota_deploy.py;
  };

  tasmota-deploy = stdenvNoCC.mkDerivation {
    pname = "tasmota-deploy";
    version = "0.1.0";
    inherit src;

    # For patchShebangs.
    buildInputs = [python3];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 tasmota_deploy.py "$out/bin/tasmota-deploy"
      runHook postInstall
    '';

    passthru = {
      # Run the Python test suite.  `args` go to `python3 -m unittest`;
      # `env` adds environment variables (e.g. NIX_MANIFEST).
      runTests = {
        name,
        args,
        env ? {},
      }:
        runCommand name ({
            nativeBuildInputs = [python3];
            # The integration tests talk to mock devices on 127.0.0.1.
            __darwinAllowLocalNetworking = true;
            PYTHONPATH = "${./tests}:${src}";
            PYTHONDONTWRITEBYTECODE = 1;
            DECODE_CONFIG = lib.getExe decode-config;
            BLANK_DUMP_ESP82 = decode-config.mkBlankDump {};
            BLANK_DUMP_ESP32 = decode-config.mkBlankDump {hardware = "ESP32ex";};
            TASMOTA_DEPLOY = lib.getExe tasmota-deploy;
          }
          // env) ''
          python3 -m unittest -v ${args}
          touch "$out"
        '';

      tests = {
        unit = tasmota-deploy.runTests {
          name = "tasmota-deploy-unit-tests";
          args = "test_unit";
        };
        integration = tasmota-deploy.runTests {
          name = "tasmota-deploy-integration-tests";
          args = "test_integration";
        };
      };
    };

    meta = {
      description = "Deploy declarative Tasmota device configurations with decode-config";
      mainProgram = "tasmota-deploy";
      platforms = lib.platforms.all;
    };
  };
in
  tasmota-deploy
