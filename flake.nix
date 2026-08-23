{
  description = "Omarchpods for NixOS — AirPods / Galaxy Buds / Beats headphone daemon and TUI (fork of MagicPodsCore)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: builtins.listToAttrs (map
        (system: {
          name = system;
          value = f (import nixpkgs { inherit system; });
        })
        systems);

      module = import ./modules/default.nix;
    in
    {
      packages = forAllSystems (pkgs: {
        omarchpods = pkgs.callPackage ./packages/omarchpods.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.omarchpods;
      });

      # Standalone entry points:
      #   nix run .#            run the core daemon (foreground)
      #   nix run .#ui          run the Textual TUI in the current terminal
      #   nix run .#launcher    open a terminal running the TUI (xdg-terminal-exec)
      #   nix run .#webui       serve the web UI on http://127.0.0.1:2021
      apps = forAllSystems (pkgs:
        let pkg = pkgs.callPackage ./packages/omarchpods.nix { }; in {
          # One command: daemon (if needed) + UI + cleanup.
          default = {
            type = "app";
            program = "${pkg}/bin/omarchpods-start";
          };
          daemon = {
            type = "app";
            program = "${pkg}/bin/omarchpods";
          };
          ui = {
            type = "app";
            program = "${pkg}/bin/omarchpods-ui";
          };
          launcher = {
            type = "app";
            program = "${pkg}/bin/omarchy-launch-omarchpods";
          };
          webui = {
            type = "app";
            program = "${pkg}/bin/omarchpods-webui";
          };
        });

      # NixOS module: { imports = [ omarchpods.nixosModules.default ]; services.omarchpods.enable = true; }
      nixosModules.default = module;
      nixosModules.omarchpods = module;

      # Overlay: provides pkgs.omarchpods
      overlays.default = final: prev: {
        omarchpods = final.callPackage ./packages/omarchpods.nix { };
      };

      checks = forAllSystems (pkgs:
        let inherit (pkgs) lib; in {
          build = pkgs.callPackage ./packages/omarchpods.nix { };
          ui-tests = import ./tests/ui-tests.nix { inherit pkgs lib; };
          dep-pins = import ./tests/dep-pins.nix { inherit pkgs lib; };
          webui-check = import ./tests/webui-check.nix { inherit pkgs lib; };
          nixos-test = import ./tests/nixos-test.nix { inherit pkgs lib; };
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "omarchpods-dev";
          packages = [
            # The built binaries are available in the dev shell too.
            (pkgs.callPackage ./packages/omarchpods.nix { })
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
