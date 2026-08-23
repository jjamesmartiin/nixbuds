# NixOS VM integration test.
#
# Boots a machine with the omarchpods module enabled and verifies that:
#   - the package is installed with all expected binaries,
#   - the systemd *user* unit is generated correctly,
#   - the core daemon starts under a real login session,
#   - the WebSocket API on localhost:2020 answers requests,
#   - the TUI launches (headless) without crashing.
{ pkgs, lib }:

let
  python = pkgs.python3.withPackages (ps: [ ps.websocket-client ]);

  # Small script that talks to the core's WebSocket API.
  wsTest = pkgs.writeScript "omarchpods-ws-test" ''
    #!${python}/bin/python
    import json
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
  name = "omarchpods";

  nodes.machine = { ... }: {
    imports = [ ../modules/default.nix ];
    services.omarchpods.enable = true;
    users.users.alice = { isNormalUser = true; };
  };

  testScript = { nodes, ... }:
    let
      pkg = nodes.machine.config.services.omarchpods.package;
    in
    ''
      start_all()

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("dbus.service")
      machine.wait_for_unit("bluetooth.service")

      # Package installed with all the expected binaries
      machine.succeed("test -x ${pkg}/bin/omarchpods")
      machine.succeed("test -x ${pkg}/bin/omarchpods-ui")
      machine.succeed("test -x ${pkg}/bin/omarchy-launch-omarchpods")
      machine.succeed("${pkg}/bin/omarchpods --version")

      # The module generated the user service unit
      machine.succeed(
          "grep -q 'ExecStart=${pkg}/bin/omarchpods' /etc/systemd/user/omarchpods.service"
      )
      machine.succeed("grep -q 'Restart=on-failure' /etc/systemd/user/omarchpods.service")

      # Core daemon starts in a real user session (as on Omarchy)
      machine.wait_for_unit("default.target", "alice")
      machine.wait_for_unit("omarchpods.service", "alice")
      machine.wait_until_succeeds("${pkgs.iproute2}/bin/ss -ltn | grep -q ':2020 '")

      # WebSocket API answers
      machine.succeed("${wsTest}")

      # TUI starts (headless; we expect it to keep running until the timeout
      # kills it, which means it did not crash on startup).
      machine.succeed("timeout 6 script -qec '${pkg}/bin/omarchpods-ui' /dev/null || test $? -eq 124")
    '';
}
