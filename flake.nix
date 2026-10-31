{
  description = "Declarative tools for managing Tasmota devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({
      flake-parts-lib,
      inputs,
      moduleWithSystem,
      ...
    }: {
      imports = [
        inputs.devshell.flakeModule
        inputs.flake-parts.flakeModules.modules
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem = {
        config,
        lib,
        pkgs,
        ...
      }: {
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

        packages = let
          sources = pkgs.callPackage ./nix/pkgs/_sources/generated.nix {};
        in {
          decode-config = pkgs.callPackage (import ./nix/pkgs/decode-config {inherit sources;}) {};
          default = config.packages.decode-config;
        };

        treefmt = let
          nixCommon = {
            enable = true;
            excludes = ["nix/pkgs/_sources/generated.nix"];
          };
        in {
          flakeFormatter = true;
          projectRootFile = "flake.nix";
          #programs.black.enable = true;
          #programs.ruff-check.enable = true;
          #programs.ruff-format.enable = true;
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
        modules = {
          tasmota = let
            decode-config = flake-parts-lib.importApply ./nix/modules/tasmota/default.nix {inherit moduleWithSystem;};
          in {
            inherit decode-config;
            default = decode-config;
          };
        };
      };
    });
}
