# NixOS module for Omarchpods.
#
# Adds the omarchpods Bluetooth headphone daemon as a systemd *user* service
# (matching upstream's Omarchy packaging) plus the Textual TUI launcher.
#
# Works both as a flake module (`nixosModules.default`) and standalone:
#
#     # configuration.nix
#     { config, pkgs, lib, ... }:
#     {
#       imports = [ /path/to/nixos-omarchpods ];
#       services.omarchpods.enable = true;
#     }
#
# The module is self-contained: if `pkgs.omarchpods` exists (e.g. via the
# overlay) it is used, otherwise the package is built from the pinned source
# in versions.nix.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.omarchpods;
in
{
  options.services.omarchpods = {
    enable = lib.mkEnableOption "the omarchpods Bluetooth headphone daemon (core service + TUI)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omarchpods or (pkgs.callPackage ../packages/omarchpods.nix { });
      defaultText = lib.literalExpression "pkgs.omarchpods or (pkgs.callPackage ../packages/omarchpods.nix { })";
      description = "The omarchpods package to use.";
    };

    bluetooth = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable BlueZ, which the daemon talks to over D-Bus.";
      };
    };

    ui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add the omarchpods Textual TUI and its launchers to system packages.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # The core daemon needs a BlueZ daemon to talk to.
    hardware.bluetooth.enable = lib.mkIf cfg.bluetooth.enable (lib.mkDefault true);

    environment.systemPackages = lib.mkIf cfg.ui.enable [
      cfg.package
    ];

    # systemd user service, as in upstream's omarchpods.service
    systemd.user.services.omarchpods = {
      description = "Omarchpods Core Service";
      documentation = [ "https://github.com/tomycostantino/omarchpods" ];
      after = [ "bluetooth.target" ];
      wants = [ "bluetooth.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/omarchpods";
        Restart = "on-failure";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
