# Overlay exposing the omarchpods package and UI as pkgs attributes.
#
#   nixpkgs.lib.nixosSystem {
#     modules = [ { nixpkgs.overlays = [ (import ./overlay.nix) ]; } ];
#   }
#
# or standalone:
#
#   let pkgs = import <nixpkgs> { overlays = [ (import ./overlay.nix) ]; }; in ...
final: prev: {
  omarchpods = final.callPackage ./packages/omarchpods.nix { };
}
