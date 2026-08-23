# Standalone entry point — lets you use this repository without flakes:
#
#     # configuration.nix
#     { ... }:
#     {
#       imports = [ /path/to/nixbuds ];
#       services.omarchpods.enable = true;
#     }
#
# Equivalent to the flake's `nixosModules.default`.
{ config, lib, pkgs, ... }:
(import ./modules/default.nix) { inherit config lib pkgs; }
