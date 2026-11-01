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
  `genJqSecretsReplacementSnippet`. Use strings, not Nix paths, for secret and
  password files so they stay out of the Nix store. Relative paths are
  resolved against the directory `tasmota-deploy` runs in.
- **Lists don't merge**: two different definitions of the same list (say, in
  `defaults` and in a device) are an error rather than being concatenated.
  Use `lib.mkDefault` in `defaults`.
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
your settings to a local copy, and compare the two. Errors such as unknown
keys show up at that point, before anything is uploaded. Password fields are
compared but their values are never printed.

The exit status is 0 when every selected device succeeded, 1 when any failed
(the others are still processed), and 2 for usage errors.

## Notes

- decode-config is patched so that it exits non-zero on errors; upstream
  v16.0.0 exits 0 after most fatal errors
  ([`nix/pkgs/decode-config/exit-code.patch`](nix/pkgs/decode-config/exit-code.patch)).
- Build-time validation uses decode-config's newest settings layout. Set a
  device's `validate = false` if it runs older firmware with settings that
  have since been removed.
- The tests use mock HTTP devices; MQTT is not tested end to end.
