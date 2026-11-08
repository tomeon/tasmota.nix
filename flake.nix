{
  description = "Declarative tools for managing Tasmota devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    # For `default.nix`, the entry point for Nix without flakes.
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({
      flake-parts-lib,
      inputs,
      lib,
      moduleWithSystem,
      self,
      ...
    }: {
      imports = [
        inputs.devshell.flakeModule
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.flake-parts.flakeModules.modules
        inputs.treefmt-nix.flakeModule
        ./nix/checks.nix
        ./nix/packages.nix
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem = {pkgs, ...}: {
        devshells.default = let
          cdToplevel = ''
            cd "''${TOPLEVEL?}" || exit
          '';
        in {
          env = [
            {
              name = "TOPLEVEL";
              eval = ''
                $(${lib.getExe pkgs.gitMinimal} rev-parse --show-toplevel 2>/dev/null || printf -- '%s' "$PRJ_ROOT")
              '';
            }
          ];

          commands = [
            {
              package = pkgs.act;
            }

            {
              package = pkgs.nvfetcher;
            }

            {
              name = "update-sources";
              category = "maintenance";
              help = "Update nvfetcher-locked sources in nix/pkgs/_sources (extra args go to nvfetcher)";
              command = ''
                ${cdToplevel}
                exec ${lib.getExe pkgs.nvfetcher} \
                  --config nix/pkgs/nvfetcher.toml \
                  --build-dir nix/pkgs/_sources \
                  "$@"
              '';
            }

            {
              name = "dedupe-inputs";
              category = "maintenance";
              help = "Add/remove flake input follows to de-duplicate flake.lock (extra args go to `flake-edit follow`)";
              command = ''
                ${cdToplevel}
                exec ${lib.getExe pkgs.flake-edit} --non-interactive follow "$@"
              '';
            }

            {
              name = "update-all";
              category = "maintenance";
              help = "Run update-sources, then dedupe-inputs";
              command = ''
                update-sources
                dedupe-inputs
              '';
            }
          ];
        };

        treefmt = let
          nixCommon = {
            enable = true;
            excludes = ["nix/pkgs/_sources/generated.nix"];
          };
        in {
          flakeFormatter = true;
          projectRootFile = "flake.nix";
          programs.ruff-check.enable = true;
          programs.ruff-format.enable = true;
          programs.alejandra = nixCommon;
          programs.deadnix =
            nixCommon
            // {
              no-lambda-pattern-names = true;
            };
          programs.statix = nixCommon;
          programs.shfmt.enable = true;
          programs.shellcheck.enable = true;
        };
      };

      flake = {
        lib = import ./nix/lib {
          inherit lib;
          tasmotaModule = self.modules.tasmota.default;
        };

        modules = let
          importModule = lib.flip flake-parts-lib.importApply;
        in {
          # `imports = [inputs.tasmota-nix.flakeModules.default];`
          flake = let
            tasmota = importModule {tasmotaLib = self.lib;} ./nix/modules/flake-parts;
          in {
            inherit tasmota;
            default = tasmota;
          };

          # The generic module; evaluate it with `lib.tasmotaConfiguration`.
          tasmota = let
            tasmota = importModule {inherit moduleWithSystem;} ./nix/modules/tasmota;
          in {
            inherit tasmota;
            default = tasmota;
          };
        };

        flakeModules = self.modules.flake;
      };
    });
}
