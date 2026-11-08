# Checks: the packages' own tests, the generic module, the flake-parts module,
# the overlay, and the flake-compat entry point.
{
  inputs,
  lib,
  self,
  ...
}: {
  perSystem = {
    config,
    pkgs,
    system,
    ...
  }: {
    checks = let
      inherit (config.packages) decode-config tasmota-deploy;
      prefix = prefix: lib.mapAttrs' (name: lib.nameValuePair "${prefix}-${name}");
    in
      prefix "decode-config" decode-config.tests
      // prefix "tasmota-deploy" tasmota-deploy.tests
      // import ./tests {
        inherit inputs lib pkgs self system tasmota-deploy;
      };
  };
}
