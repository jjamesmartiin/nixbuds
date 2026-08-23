{
  description = "Omarchpods for NixOS — AirPods / Galaxy Buds / Beats headphone daemon and TUI (fork of MagicPodsCore)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: builtins.listToAttrs (map (system: {
        name = system;
        value = f (import nixpkgs { inherit system; });
      }) systems);

      module = import ./modules/default.nix;
    in
    {
      packages = forAllSystems (pkgs: {
        omarchpods = pkgs.callPackage ./packages/omarchpods.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.omarchpods;
      });

      # NixOS module: { imports = [ omarchpods.nixosModules.default ]; services.omarchpods.enable = true; }
      nixosModules.default = module;
      nixosModules.omarchpods = module;

      # Overlay: provides pkgs.omarchpods
      overlays.default = final: prev: {
        omarchpods = final.callPackage ./packages/omarchpods.nix { };
      };

      checks = forAllSystems (pkgs: {
        build = pkgs.callPackage ./packages/omarchpods.nix { };
        ui-tests = import ./tests/ui-tests.nix { inherit pkgs; };
        dep-pins = import ./tests/dep-pins.nix { inherit pkgs; };
        nixos-test = import ./tests/nixos-test.nix { inherit pkgs; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "omarchpods-dev";
          packages = [
            pkgs.cmake
            pkgs.pkg-config
            pkgs.git
            pkgs.zlib
            pkgs.bluez
            pkgs.systemdLibs
            (pkgs.python3.withPackages (ps: [ ps.textual ps.websocket-client ps.pytest ]))
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
