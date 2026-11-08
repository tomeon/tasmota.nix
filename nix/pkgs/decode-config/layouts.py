"""Derive data from decode-config's settings layouts, for offline validation.

layouts.py blank [--hardware NAME] DECODE_CONFIG_PY OUTPUT
    Write a blank but valid configuration dump (.dmp) in the newest
    layout: every field zeroed except the ones decode-config needs to
    accept it (version, size, hardware platform and CRC).  It stands in
    for a real device when validating settings offline and in tests.

layouts.py keys DECODE_CONFIG_PY DECODE_CONFIG OUTPUT
    Write the structure of decoded settings (JSON), merged over every
    hardware platform: objects map keys to structures, lists hold one
    merged element structure, and plain values are null.  DECODE_CONFIG
    is the executable used to decode the blank dumps.
"""

import argparse
import importlib.util
import json
import os
import struct
import subprocess
import tempfile


def load_decode_config(path):
    spec = importlib.util.spec_from_file_location("decode_config", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def blank_dump(dc, config_version):
    """Blank dump for the platform with the given `config_version` index."""
    version, size, template = max(dc.SETTINGS, key=lambda s: s[0])
    buf = bytearray(size)

    def put(name, value):
        fielddef = template[name]
        fmt, addr = fielddef[1], fielddef[2]
        struct.pack_into(fmt, buf, addr, value)

    put("version", version)
    put("cfg_size", size)
    put("config_version", config_version)
    put("cfg_crc32", dc.get_settingcrc32(buf[:size]))
    return bytes(dc.decrypt_encrypt(buf))


def structure(value):
    if isinstance(value, dict):
        return {k: structure(v) for k, v in value.items()}
    if isinstance(value, list):
        merged = None
        for item in value:
            merged = merge(merged, structure(item))
        return [] if merged is None and not value else [merged]
    return None


def merge(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if isinstance(a, dict) and isinstance(b, dict):
        return {k: merge(a.get(k), b.get(k)) for k in a.keys() | b.keys()}
    if isinstance(a, list) and isinstance(b, list):
        return [merge(a[0] if a else None, b[0] if b else None)] if a or b else []
    return a


def keys(dc, executable):
    merged = None
    with tempfile.TemporaryDirectory() as tmp:
        for index in range(len(dc.HARDWARE.config_versions)):
            dump = os.path.join(tmp, f"{index}.dmp")
            with open(dump, "wb") as f:
                f.write(blank_dump(dc, index))
            out = subprocess.run(
                [executable, "--source", dump, "--json-show-pw"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            config = json.loads(out)
            config.pop("header", None)
            merged = merge(merged, structure(config))
    return merged


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    blank = sub.add_parser("blank")
    blank.add_argument(
        "--hardware",
        default="ESP82",
        help="HARDWARE attribute name from decode-config, e.g. ESP82 or ESP32ex",
    )
    blank.add_argument("decode_config_py")
    blank.add_argument("output")
    key = sub.add_parser("keys")
    key.add_argument("decode_config_py")
    key.add_argument("decode_config")
    key.add_argument("output")
    args = parser.parse_args()

    dc = load_decode_config(args.decode_config_py)
    if args.command == "blank":
        index = dc.HARDWARE.config_versions.index(getattr(dc.HARDWARE, args.hardware))
        with open(args.output, "wb") as out:
            out.write(blank_dump(dc, index))
    else:
        with open(args.output, "w", encoding="utf-8") as out:
            json.dump(keys(dc, args.decode_config), out, sort_keys=True)


if __name__ == "__main__":
    main()
