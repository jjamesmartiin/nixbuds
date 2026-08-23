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
#       imports = [ /path/to/nixbuds ];
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

    webui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Serve the omarchpods web UI on http://127.0.0.1:<port> as a systemd user service.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 2021;
        description = "Port for the web UI.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # The core daemon needs a BlueZ daemon to talk to. Make sure the target
    # BlueZ is wanted by actually gets reached at boot (on desktop systems
    # something usually pulls it in already; on minimal setups this makes it
    # deterministic).
    hardware.bluetooth.enable = lib.mkIf cfg.bluetooth.enable (lib.mkDefault true);
    systemd.targets.bluetooth = lib.mkIf cfg.bluetooth.enable {
      wantedBy = [ "multi-user.target" ];
    };

    environment.systemPackages = lib.mkIf cfg.ui.enable [
      cfg.package
    ];

    # systemd user service, as in upstream's omarchpods.service
    systemd.user.services.nixbuds = {
      description = "nixbuds Core Service";
      documentation = [ "https://github.com/tomycostantino/omarchpods" ];
      after = [ "bluetooth.target" ];
      wants = [ "bluetooth.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/nixbuds-core";
        Restart = "on-failure";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Optional web UI served on 127.0.0.1 (user service).
    systemd.user.services.nixbuds-webui = lib.mkIf cfg.webui.enable {
      description = "nixbuds Web UI";
      documentation = [ "https://github.com/tomycostantino/omarchpods" ];
      after = [ "nixbuds.service" ];
      wants = [ "nixbuds.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/nixbuds-webui --port ${toString cfg.webui.port}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
