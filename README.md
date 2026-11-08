# tasmota.nix

Declarative configuration for [Tasmota](https://tasmota.github.io/) devices,
applied with [decode-config](https://github.com/tasmota/decode-config).

You describe each device's settings as partial decode-config JSON in Nix;
`tasmota-deploy` shows what would change and uploads only to devices whose
configuration differs (Tasmota reboots after every upload).

## Configuration

```nix
{lib, ...}: {
  decode-config = {
    # Applied to every device.
    defaults = {
      tags = ["home"];
      settings.mqtt_host = lib.mkDefault "broker.lan";
    };

    devices.kitchen = {
      source = "http://kitchen.lan";              # decode-config --source; defaults to the name
      passwordFile = "/run/secrets/tasmota-web";  # read when deploying
      tags = ["lights"];
      settings = {
        friendlyname = ["Kitchen"];
        sta_ssid = ["home"];
        sta_pwd = [{_secret = "/run/secrets/wifi";}];
      };
    };
  };
}
```

- **`settings`** are decode-config JSON keys. Only the keys you give are
  written; everything else on the device stays as it is. A shorter list sets
  only the first elements of a Tasmota array. `tasmota-deploy pull` prints a
  device's current settings, which is the easiest way to find key names.
- **Secrets**: `{_secret = "/path";}` anywhere in `settings` is replaced with
  the file's contents (minus trailing newlines) at deploy time, as in nixpkgs'
  `genJqSecretsReplacementSnippet`. Secret and password files must be absolute
  paths given as strings, not Nix paths, so they stay out of the Nix store.
- **Lists don't merge**: defining the same list in two places (say, in
  `defaults` and in a device) is an error rather than a concatenation, since
  Tasmota arrays are positional. Use `lib.mkDefault` in `defaults`.
- **MQTT sources** (`mqtt://` / `mqtts://`) are handed to decode-config the
  same way as HTTP ones, with `passwordFile` as the broker password; pass TLS
  and topic options through `extraArgs`.

The options live under `decode-config` so that other namespaces can be added
alongside it.

## Using it

### flake-parts

```nix
{
  inputs.tasmota-nix.url = "github:tomeon/tasmota.nix";

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.tasmota-nix.modules.flake.default];
      systems = ["x86_64-linux"];
      tasmota = ./tasmota.nix;  # the configuration above
    };
}
```

This adds `packages.<system>.tasmota-deploy` (with the configuration built in)
and `checks.<system>.tasmota-validation`:

```console
$ nix run .#tasmota-deploy -- diff
$ nix run .#tasmota-deploy -- switch --on @lights
```

### Without flakes

```nix
# fleet.nix
let
  tasmota = import (fetchTarball "https://github.com/tomeon/tasmota.nix/archive/main.tar.gz") {};
in
  (tasmota.evalConfig {modules = [./tasmota.nix];}).config.decode-config.build.deployer
```

```console
$ nix-build fleet.nix && ./result/bin/tasmota-deploy diff
```

`import ... {}` uses the nixpkgs revision pinned in this repository's
`flake.lock`; pass `{pkgs = ...;}` to use your own. Flake users who don't use
flake-parts can call `inputs.tasmota-nix.lib.evalConfig {pkgs = ...; modules = [...];}`.

## tasmota-deploy

| Command  | What it does                                                         |
| -------- | -------------------------------------------------------------------- |
| `build`  | Check settings offline against a blank configuration; no device access |
| `diff`   | Download each device's configuration and show what `switch` would change |
| `switch` | Apply settings to devices whose configuration would change           |
| `pull`   | Print devices' current settings as JSON (passwords hidden); `-o DIR` writes files |

Options: `--on kitchen,@lights` selects devices by name or tag, `-j N` sets
parallelism (default 4), `--timeout S` limits each decode-config run, and
`switch --backup-dir DIR` saves each device's previous configuration (`.dmp`)
before changing it. Restore a backup with
`decode-config.py -s <device> -i <file>.dmp`.

For each device, `diff` and `switch` download the configuration once, apply
your settings to a local copy, and compare the two. Errors show up at that
point, before anything is uploaded: invalid values, and keys the device's
configuration doesn't have (decode-config itself silently ignores misspelled
nested keys and keys for other hardware). `build` checks keys against every
hardware platform's layout and values against a blank ESP8266 configuration.

Password fields and values declared with `_secret` are compared but never
printed, secret values are scrubbed from decode-config's error messages, and
backups and `pull -o` files are created readable only by you (configuration
dumps contain recoverable credentials).

The exit status is 0 when every selected device succeeded, 1 when any failed
(the others are still processed), and 2 for usage errors.

## Notes

- decode-config is patched so that it exits non-zero on errors; upstream
  v16.0.0 exits 0 after most fatal errors
  ([`nix/pkgs/decode-config/exit-code.patch`](nix/pkgs/decode-config/exit-code.patch)).
- Build-time validation uses decode-config's newest settings layout. Set a
  device's `validate = false` if it runs older firmware with settings that
  have since been removed.
- Over plain `http://`, the web password (HTTP basic auth) and the
  configuration itself, including Wi-Fi and MQTT passwords that Tasmota only
  obfuscates, cross the network unencrypted. Deploy from a network you trust.
- Each device needs its own `source`; `tasmota-deploy` refuses manifests in
  which two devices point at the same one, since their settings would race.
- `switch` reports success once the device accepts the upload. It does not
  wait for the restart and check again, because settings such as Wi-Fi can
  move the device away from the address it was deployed to. Run `diff`
  afterwards to confirm.
- The tests use mock HTTP devices; MQTT is not tested end to end.
