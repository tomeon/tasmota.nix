{sources}: {
  lib,
  python3Packages,
  ...
}:
python3Packages.buildPythonApplication {
  inherit (sources.decode-config) pname src version;
  pyproject = true;
  build-system = with python3Packages; [setuptools];
  propagatedBuildInputs = with python3Packages; [
    requests
    configargparse
    paho-mqtt
  ];
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
}
