"""Write a blank but valid Tasmota configuration dump (.dmp).

The dump uses the newest settings layout that decode-config knows about,
with every field zeroed except the ones decode-config needs to accept it
(version, size, hardware platform and CRC).  It stands in for a real device
when validating configurations offline and in tests.

Usage: blank-dump.py [--hardware NAME] DECODE_CONFIG_PY OUTPUT
"""

import argparse
import importlib.util
import struct


def load_decode_config(path):
    spec = importlib.util.spec_from_file_location("decode_config", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def blank_dump(dc, hardware):
    version, size, template = max(dc.SETTINGS, key=lambda s: s[0])
    buf = bytearray(size)

    def put(name, value):
        fielddef = template[name]
        fmt, addr = fielddef[1], fielddef[2]
        struct.pack_into(fmt, buf, addr, value)

    put("version", version)
    put("cfg_size", size)
    put(
        "config_version",
        dc.HARDWARE.config_versions.index(getattr(dc.HARDWARE, hardware)),
    )
    put("cfg_crc32", dc.get_settingcrc32(buf[:size]))
    return bytes(dc.decrypt_encrypt(buf))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--hardware",
        default="ESP82",
        help="HARDWARE attribute name from decode-config, e.g. ESP82 or ESP32ex",
    )
    parser.add_argument("decode_config", help="path to decode-config.py")
    parser.add_argument("output")
    args = parser.parse_args()

    dc = load_decode_config(args.decode_config)
    with open(args.output, "wb") as out:
        out.write(blank_dump(dc, args.hardware))


if __name__ == "__main__":
    main()
