{
  lib,
  tasmotaModule,
}: {
  /**
  Evaluate tasmota.nix configuration modules with the generic module.

  The result is a `lib.evalModules` result: `config.build.deployer` is
  `tasmota-deploy` with the configuration built in, `config.build.validation`
  checks it offline.

  # Inputs

  `system`
  : The system to build the tools for.  Defaults to `builtins.currentSystem`
    where that is available (Nix without flakes, or `--impure`).

  `modules`
  : A module or a list of modules.

  Other arguments (`specialArgs`, `prefix`, ...) are passed to
  `lib.evalModules`.  `class` is always `"tasmota"`.

  # Example

  ```nix
  tasmotaConfiguration {
    system = "x86_64-linux";
    modules = {fleet.devices.kitchen.settings.friendlyname = ["Kitchen"];};
  }
  ```
  */
  tasmotaConfiguration = {
    system ? builtins.currentSystem or (throw "tasmotaConfiguration: pass `system`, e.g. \"x86_64-linux\"."),
    modules ? [],
    ...
  } @ args:
    lib.evalModules (removeAttrs args ["system"]
      // {
        class = "tasmota";
        modules =
          [
            tasmotaModule
            {_module.args.system = system;}
          ]
          ++ lib.toList modules;
      });
}
