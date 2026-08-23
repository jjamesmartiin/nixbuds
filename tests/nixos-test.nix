# NixOS VM integration test.
#
# Boots a machine with the omarchpods module enabled and verifies that:
#   - the package is installed with all expected binaries,
#   - the systemd *user* unit is generated correctly,
#   - BlueZ wiring is in place (bluetooth.target reached at boot; on a real
#     machine bluetooth.service starts, in the VM it is skipped because there
#     is no Bluetooth hardware),
#   - the core daemon starts under a real login session even without BlueZ,
#   - the WebSocket API on localhost:2020 answers requests,
#   - the TUI launches (headless) without crashing.
{ pkgs, lib }:

let
  python = pkgs.python3.withPackages (ps: [ ps.websocket-client ]);

  # Small script that talks to the core's WebSocket API.
  wsTest = pkgs.writeScript "nixbuds-ws-test" ''
    #!${python}/bin/python
    import json
    import sys
    import websocket

    ws = websocket.create_connection("ws://localhost:2020", timeout=10)
    ws.send(json.dumps({"method": "GetAll"}))
    data = json.loads(ws.recv())
    assert "headphones" in data, data
    assert "defaultbluetooth" in data, data
    assert "info" in data, data
    ws.close()
    print("GetAll OK:", json.dumps(data)[:200])
  '';
in
pkgs.testers.runNixOSTest {
  name = "nixbuds";

  nodes.machine = { pkgs, ... }: {
    # Use the standalone module entry point (./default.nix) on purpose — this
    # is the non-flake way of importing the module.
    imports = [ ../default.nix ];
    services.omarchpods.enable = true;
    services.omarchpods.webui.enable = true;
    users.users.alice = { isNormalUser = true; };
    # Real login session so the systemd *user* service actually starts.
    services.getty.autologinUser = "alice";
    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = { nodes, ... }:
    let
      pkg = nodes.machine.services.omarchpods.package;
    in
    ''
      start_all()

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("dbus.service")

      # The module pulls in BlueZ support; bluetooth.service itself is skipped
      # in this VM (no Bluetooth hardware) but the target must be reached.
      machine.wait_for_unit("bluetooth.target")

      # Package installed with all the expected binaries
      machine.succeed("test -x ${pkg}/bin/nixbuds")
      machine.succeed("test -x ${pkg}/bin/nixbuds-ui")
      machine.succeed("test -x ${pkg}/bin/nixbuds-launch")
      machine.succeed("${pkg}/bin/nixbuds --version")

      # The module generated the user service unit
      machine.succeed(
          "grep -q 'ExecStart=${pkg}/bin/nixbuds' /etc/systemd/user/nixbuds.service"
      )
      machine.succeed("grep -q 'Restart=on-failure' /etc/systemd/user/nixbuds.service")

      # Core daemon starts in a real user session (as on Omarchy)
      machine.wait_for_unit("default.target", "alice")
      machine.wait_for_unit("nixbuds.service", "alice")
      machine.wait_until_succeeds("${pkgs.iproute2}/bin/ss -ltn | grep -q ':2020 '")

      # WebSocket API answers even without a BlueZ adapter
      machine.succeed("${wsTest}")

      # If we can bring up bluetoothd manually (no adapter in the VM, but the
      # daemon still registers on the bus), the core must keep working.
      machine.succeed(
          "systemd-run --unit=manual-bluetoothd ${pkgs.bluez}/libexec/bluetooth/bluetoothd -n -f /etc/bluetooth/main.conf || true"
      )
      machine.succeed("${wsTest}")

      # TUI starts (headless; we expect it to keep running until the timeout
      # kills it, which means it did not crash on startup).
      machine.succeed("timeout 6 script -qec '${pkg}/bin/nixbuds-ui' /dev/null || test $? -eq 124")

      # Web UI: the user service serves the static page, which talks to the
      # daemon WebSocket.
      machine.wait_for_unit("nixbuds-webui.service", "alice")
      machine.wait_until_succeeds("curl -fsS http://127.0.0.1:2021/ | grep -q '<title>Omarchpods</title>'")
      machine.succeed("curl -fsS http://127.0.0.1:2021/app.js | grep -q 'ws://localhost:2020'")
      machine.succeed("curl -fsS http://127.0.0.1:2021/styles.css | grep -q ':root'")
    '';
}
