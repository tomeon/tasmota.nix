{
  description = "Declarative tools for managing Tasmota devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";

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
        pkgs,
        ...
      }: {
        devshells.default = {
          commands = [
            {
              package = pkgs.nvfetcher;
            }
          ];
        };

        packages = let
          sources = pkgs.callPackage ./nix/pkgs/_sources/generated.nix {};
        in {
          decode-config = pkgs.callPackage (import ./nix/pkgs/decode-config {inherit sources;}) {};
          default = config.packages.decode-config;
        };

        treefmt = {
          flakeFormatter = true;
          projectRootFile = "flake.nix";
          #programs.black.enable = true;
          #programs.ruff-check.enable = true;
          #programs.ruff-format.enable = true;
          programs.alejandra.enable = true;
          programs.deadnix.enable = true;
          programs.statix.enable = true;
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
