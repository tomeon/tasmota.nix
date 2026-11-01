{sources}: {
  lib,
  python3Packages,
  runCommand,
  ...
}: let
  dependencies = with python3Packages; [
    requests
    configargparse
    paho-mqtt
  ];

  decode-config = python3Packages.buildPythonApplication {
    inherit (sources.decode-config) pname src version;
    pyproject = true;
    build-system = with python3Packages; [setuptools];
    propagatedBuildInputs = dependencies;

    # decode-config exits 0 after most fatal errors, because its `log()`
    # overwrites the recorded exit code when it reports "Premature exit".
    patches = [./exit-code.patch];

    passthru = {
      # Blank, valid configuration dump for offline validation and tests.
      # `hardware` is a `HARDWARE` attribute name from decode-config
      # (e.g. "ESP82", "ESP32ex").
      mkBlankDump = {hardware ? "ESP82"}:
        runCommand "tasmota-blank-${hardware}.dmp" {
          nativeBuildInputs = [(python3Packages.python.withPackages (_: dependencies))];
        } ''
          python3 -I ${./blank-dump.py} --hardware ${lib.escapeShellArg hardware} \
            ${decode-config.src}/decode-config.py "$out"
        '';

      tests.exit-codes = runCommand "decode-config-exit-codes" {nativeBuildInputs = [decode-config];} ''
        expect() {
          local want=$1 rc=0
          shift
          decode-config.py "$@" >/dev/null 2>&1 || rc=$?
          if [ "$rc" -ne "$want" ]; then
            echo "expected exit $want, got $rc: decode-config.py $*" >&2
            exit 1
          fi
        }
        cp ${decode-config.mkBlankDump {}} dev.dmp
        chmod u+w dev.dmp
        echo '{"hostname": "test"}' > good.json
        echo '{"no_such_key": 1}' > bad.json

        expect 0 -s dev.dmp -i good.json   # changed
        expect 1 -s dev.dmp -i good.json   # restore skipped: unchanged
        expect 9 -s dev.dmp -i bad.json    # restore data error: unknown key
        expect 3 -s dev.dmp -i missing.json # file not found
        touch $out
      '';
    };

    meta = {
      description = "Backup/restore and decode configuration tool for Tasmota";
      longDescription = ''
        Convert, backup and restore configuration data of devices flashed with
        Tasmota firmware.  decode-config creates readable and editable JSON
        from the binary configuration data of Tasmota, which is otherwise
        protected against changes by a checksum.  It can read and write
        directly from online devices (via HTTP or MQTT) or from offline files
        in binary format, process subsets of the configuration, convert data
        between Tasmota versions (from 5.10.0 onwards), and generate a list of
        Tasmota commands for most configuration-related settings.
      '';
      homepage = "https://github.com/tasmota/decode-config";
      changelog = "https://github.com/tasmota/decode-config/releases/tag/${sources.decode-config.version}";
      license = with lib.licenses; [lgpl3Only];
      mainProgram = "decode-config.py";
      platforms = lib.platforms.all;
    };
  };
in
  decode-config
