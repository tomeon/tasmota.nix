import json
import os
import tempfile
import unittest

import tasmota_deploy as td


def devices(**tags):
    return {name: td.Device(name=name, source=name, tags=t) for name, t in tags.items()}


class SelectDevices(unittest.TestCase):
    fleet = devices(kitchen=["lights"], hall=["lights", "upstairs"], plug=[])

    def names(self, selector):
        return [d.name for d in td.select_devices(self.fleet, selector)]

    def test_all_by_default(self):
        self.assertEqual(self.names(None), ["hall", "kitchen", "plug"])

    def test_names_and_tags(self):
        self.assertEqual(self.names("plug,@upstairs"), ["hall", "plug"])
        self.assertEqual(self.names("@lights, kitchen"), ["hall", "kitchen"])

    def test_unknown_name(self):
        with self.assertRaisesRegex(td.DeployError, "unknown device 'attic'"):
            self.names("attic")

    def test_unknown_tag(self):
        with self.assertRaisesRegex(td.DeployError, "no device has tag 'nope'"):
            self.names("@nope")

    def test_empty(self):
        with self.assertRaisesRegex(td.DeployError, "no devices selected"):
            self.names(",")


class Secrets(unittest.TestCase):
    def test_resolve_nested(self):
        settings = {
            "sta_pwd": [{"_secret": "a"}, ""],
            "nested": {"x": {"_secret": "b"}, "y": 1},
            "not_a_ref": {"_secret": "c", "other": 1},
        }
        got = td.resolve_secrets(settings, lambda p: p.upper())
        self.assertEqual(
            got,
            {
                "sta_pwd": ["A", ""],
                "nested": {"x": "B", "y": 1},
                "not_a_ref": {"_secret": "c", "other": 1},
            },
        )

    def test_read_secret_strips_trailing_newlines(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "s")
            with open(path, "w") as f:
                f.write("  hunter2 \n\n")
            self.assertEqual(td.read_secret(path), "  hunter2 ")

    def test_read_secret_missing(self):
        with self.assertRaisesRegex(td.DeployError, "cannot read secret"):
            td.read_secret("/nonexistent/secret")


class PasswordConfig(unittest.TestCase):
    def test_quoted(self):
        self.assertEqual(td.password_config('a # "b'), 'password = "a # "b"\n')

    def test_rejects_newline(self):
        with self.assertRaises(td.DeployError):
            td.password_config("a\nb")

    def test_rejects_list_syntax(self):
        with self.assertRaises(td.DeployError):
            td.password_config("[a]")


class Diff(unittest.TestCase):
    def test_leaf_paths(self):
        before = {"a": 1, "b": {"c": [1, 2]}, "d": [1], "e": "x"}
        after = {"a": 1, "b": {"c": [1, 3]}, "d": [1, 2], "e": "y"}
        self.assertEqual(
            list(td.diff_values(before, after)),
            [("b.c[1]", 2, 3), ("d", [1], [1, 2]), ("e", "x", "y")],
        )

    def test_ignores_top_level_checksums(self):
        before = {"cfg_crc32": "0x1", "cfg_crc": "0x2", "x": {"cfg_crc": 1}}
        after = {"cfg_crc32": "0x3", "cfg_crc": "0x4", "x": {"cfg_crc": 2}}
        self.assertEqual(list(td.diff_values(before, after)), [("x.cfg_crc", 1, 2)])

    def test_format(self):
        self.assertEqual(
            td.format_changes([("hostname", "", "lamp")]),
            ['  hostname: "" -> "lamp"'],
        )

    def test_format_hidden(self):
        self.assertEqual(
            td.format_changes([("sta_pwd[0]", "old", "new")], {"sta_pwd[0]"}),
            ["  sta_pwd[0]: changed (hidden)"],
        )

    def test_leaves_match_diff_paths(self):
        value = {"a": [1, {"b": 2}], "c": 3}
        self.assertEqual(list(td.leaves(value)), [("a[0]", 1), ("a[1].b", 2), ("c", 3)])


def write_json(test, data):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(data, f)
    test.addCleanup(os.unlink, f.name)
    return f.name


class Manifest(unittest.TestCase):
    def write(self, data):
        return write_json(self, data)

    def test_load(self):
        path = self.write(
            {
                "version": 1,
                "decodeConfig": "/bin/dc",
                "devices": {"lamp": {"source": "http://lamp", "tags": ["t"]}},
            }
        )
        m = td.load_manifest(path)
        self.assertEqual(m.decode_config, "/bin/dc")
        self.assertIsNone(m.blank_dump)
        self.assertEqual(m.devices["lamp"].tags, ["t"])
        self.assertTrue(m.devices["lamp"].validate)

    def test_wrong_version(self):
        path = self.write({"version": 99, "decodeConfig": "x", "devices": {}})
        with self.assertRaisesRegex(td.DeployError, "version 99"):
            td.load_manifest(path)

    def test_unreadable(self):
        with self.assertRaisesRegex(td.DeployError, "cannot read manifest"):
            td.load_manifest("/nonexistent.json")


class Args(unittest.TestCase):
    def test_jobs_must_be_positive(self):
        with self.assertRaises(SystemExit):
            td.parse_args(["--manifest", "m", "diff", "-j", "0"])

    def test_bad_selector_exit_code(self):
        path = write_json(self, {"version": 1, "decodeConfig": "x", "devices": {}})
        self.assertEqual(td.main(["--manifest", path, "diff", "--on", "x"]), 2)


if __name__ == "__main__":
    unittest.main()
