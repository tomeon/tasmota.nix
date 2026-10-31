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
      Tasmota firmware.
    '';
    license = with lib.licenses; [lgpl3Only];
    mainProgram = "decode-config.py";
  };
}
