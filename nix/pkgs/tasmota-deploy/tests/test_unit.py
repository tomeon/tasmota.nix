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


SECRET_SETTINGS = {"sta_pwd": ["", {"_secret": "a"}], "x": {"y": {"_secret": "b"}}}


class SecretPaths(unittest.TestCase):
    def test_secret_paths(self):
        self.assertEqual(
            sorted(td.secret_paths(SECRET_SETTINGS)), ["sta_pwd[1]", "x.y"]
        )

    def test_mask_paths(self):
        config = {"sta_pwd": ["p0", "p1"], "x": {"y": "v", "z": "w"}}
        masked = td.mask_paths(config, set(td.secret_paths(SECRET_SETTINGS)))
        self.assertEqual(
            masked, {"sta_pwd": ["p0", "********"], "x": {"y": "********", "z": "w"}}
        )


class Redact(unittest.TestCase):
    def test_redacts_raw_and_escaped_forms(self):
        dc = td.DecodeConfig("dc", td.Device(name="d", source="d"), "/tmp", 1)
        backslash, accent = "pa\\ss", "caf\u00e9"
        dc.secrets.update({backslash, accent})
        text = " ".join(
            [backslash, repr(backslash)[1:-1], accent, json.dumps(accent)[1:-1]]
        )
        self.assertEqual(dc.redact(text), " ".join(["<secret>"] * 4))


KNOWN = {"flag": {"mqtt_enabled": 0}, "timer": [{"arm": 0}], "hostname": ""}


class UnknownKeys(unittest.TestCase):
    def unknown(self, supplied):
        return list(td.unknown_keys(supplied, KNOWN))

    def test_known(self):
        self.assertEqual(
            self.unknown({"flag": {"mqtt_enabled": 1}, "hostname": "h"}), []
        )

    def test_nested_typo(self):
        self.assertEqual(
            self.unknown({"flag": {"mqtt_enabeld": 1}}), ["flag.mqtt_enabeld"]
        )

    def test_top_level_typo(self):
        self.assertEqual(self.unknown({"hostnmae": "h"}), ["hostnmae"])

    def test_list_elements(self):
        self.assertEqual(
            self.unknown({"timer": [{"arm": 1}, {"armm": 1}]}), ["timer[1].armm"]
        )

    def test_object_for_plain_value(self):
        self.assertEqual(self.unknown({"hostname": {"a": 1}}), ["hostname"])


class WritePrivate(unittest.TestCase):
    def test_mode_and_replace(self):
        old = os.umask(0o022)
        self.addCleanup(os.umask, old)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "f")
            td.write_private(path, b"one")
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                td.write_private(path, b"two")
            os.chmod(path, 0o644)
            td.write_private(path, "three", replace=True)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            with open(path) as f:
                self.assertEqual(f.read(), "three")


class WritePrivateSymlinks(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.target = os.path.join(tmp.name, "target")
        with open(self.target, "w") as f:
            f.write("keep")
        os.chmod(self.target, 0o644)
        self.link = os.path.join(tmp.name, "link")
        os.symlink(self.target, self.link)

    def test_replace_replaces_the_link_not_its_target(self):
        td.write_private(self.link, "new", replace=True)
        with open(self.target) as f:
            self.assertEqual(f.read(), "keep")
        self.assertEqual(os.stat(self.target).st_mode & 0o777, 0o644)
        self.assertFalse(os.path.islink(self.link))
        self.assertEqual(os.stat(self.link).st_mode & 0o777, 0o600)
        with open(self.link) as f:
            self.assertEqual(f.read(), "new")

    def test_exclusive_refuses_a_link(self):
        with self.assertRaises(FileExistsError):
            td.write_private(self.link, b"new")
        with open(self.target) as f:
            self.assertEqual(f.read(), "keep")


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

    def test_shared_target_is_rejected(self):
        devices = {
            "a": {"source": "Kitchen.lan"},
            "b": {"source": "http://admin@kitchen.lan:80/"},
            "c": {"source": "mqtt://broker/tasmota_c"},
            "d": {"source": "mqtt://broker:1883/tasmota_c"},
            "e": {"source": "mqtt://broker/tasmota_e"},
        }
        path = self.write({"version": 1, "decodeConfig": "x", "devices": devices})
        with self.assertRaisesRegex(td.DeployError, r"share a source.*: a, b; c, d$"):
            td.load_manifest(path)

    def test_distinct_mqtt_topics_from_extra_args(self):
        devices = {
            "a": {
                "source": "mqtt://broker",
                "extraArgs": ["--fulltopic", "a/%prefix%/"],
            },
            "b": {"source": "mqtt://broker", "extraArgs": ["--fulltopic=b/%prefix%/"]},
        }
        path = self.write({"version": 1, "decodeConfig": "x", "devices": devices})
        self.assertEqual(sorted(td.load_manifest(path).devices), ["a", "b"])

    def test_target(self):
        self.assertEqual(td.target("lamp"), ("http", "lamp", 80, ""))
        self.assertNotEqual(td.target("https://lamp"), td.target("http://lamp"))
        self.assertEqual(td.target("http://lamp:bad"), "http://lamp:bad")

    def test_target_http_ignores_path(self):
        # decode-config reaches HTTP devices by host and port alone.
        self.assertEqual(td.target("http://lamp/cs?"), td.target("lamp"))

    def test_target_port_from_extra_args(self):
        want = td.target("http://lamp:8080")
        self.assertEqual(td.target("lamp", ["-P", "8080"]), want)
        self.assertEqual(td.target("lamp", ["-P8080"]), want)
        self.assertEqual(td.target("lamp", ["--port=8080"]), want)
        self.assertEqual(td.target("http://lamp:8080", ["--port", "1"]), want)

    def test_target_mqtt_topic(self):
        url_topic = td.target("mqtt://broker/t")
        self.assertEqual(td.target("mqtt://broker/t", ["--fulltopic", "x"]), url_topic)
        self.assertEqual(td.target("mqtt://broker", ["--fulltopic", "t"]), url_topic)
        self.assertNotEqual(
            td.target("mqtt://broker", ["--fulltopic", "x"]), td.target("mqtt://broker")
        )

    def test_target_files(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ("a.dmp", "b.dmp"):
                with open(os.path.join(d, name), "wb"):
                    pass
            a, b = os.path.join(d, "a.dmp"), os.path.join(d, "b.dmp")
            self.assertNotEqual(td.target(a), td.target(b))
            self.assertEqual(td.target(a), td.target("file://" + a))
            self.assertEqual(td.target(a), td.target(os.path.relpath(a)))

    def test_wrong_version(self):
        path = self.write({"version": 99, "decodeConfig": "x", "devices": {}})
        with self.assertRaisesRegex(td.DeployError, "version 99"):
            td.load_manifest(path)

    def test_unreadable(self):
        with self.assertRaisesRegex(td.DeployError, "cannot read manifest"):
            td.load_manifest("/nonexistent.json")


class ExtraArgs(unittest.TestCase):
    def test_allowed(self):
        for args in (
            ["--fulltopic", "%prefix%/%topic%/"],
            ["--fulltopic=%prefix%/%topic%/"],
            ["-P", "8080"],
            ["-P8080", "--insecure"],
            ["--cafile", "/etc/ca.pem", "--keepalive", "30"],
            ["-g", "Wifi", "Mqtt", "-u", "admin"],
            [],
        ):
            td.check_extra_args(args)

    def test_refused(self):
        for args in (
            ["--source", "http://other"],
            ["-s", "http://other"],
            ["--sour", "http://other"],  # decode-config accepts abbreviations
            ["-c", "conf"],
            ["-p", "password"],
            ["--dry-run"],
            ["-w"],
            ["--json-hide-pw"],
            ["--restore-file", "x.json"],
            ["stray"],
        ):
            with self.assertRaisesRegex(td.DeployError, "not allowed", msg=args):
                td.check_extra_args(args)

    def test_values(self):
        for args, message in (
            (["--fulltopic"], "needs a value"),
            (["-P", "--insecure"], "needs a value"),
            (["-g"], "needs a value"),
            (["--insecure=yes"], "takes no value"),
            (["-P", "1", "2"], "not allowed"),
        ):
            with self.assertRaisesRegex(td.DeployError, message, msg=args):
                td.check_extra_args(args)

    def test_manifest_refuses_source_override(self):
        devices = {
            "a": {"source": "http://a", "extraArgs": ["--source", "http://b"]},
            "b": {"source": "http://b"},
        }
        path = write_json(self, {"version": 1, "decodeConfig": "x", "devices": devices})
        with self.assertRaisesRegex(td.DeployError, "device 'a': extraArgs"):
            td.load_manifest(path)


class Args(unittest.TestCase):
    def test_jobs_must_be_positive(self):
        with self.assertRaises(SystemExit):
            td.parse_args(["--manifest", "m", "diff", "-j", "0"])

    def test_bad_selector_exit_code(self):
        path = write_json(self, {"version": 1, "decodeConfig": "x", "devices": {}})
        self.assertEqual(td.main(["--manifest", path, "diff", "--on", "x"]), 2)


if __name__ == "__main__":
    unittest.main()
