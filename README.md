# nixos-omarchpods

Nix packaging for [omarchpods](https://github.com/tomycostantino/omarchpods) —
a fork of [MagicPodsCore](https://github.com/steam3d/MagicPodsCore) that manages
Bluetooth headphones (AirPods, Galaxy Buds, Beats, …) on Linux: battery levels,
ANC / transparency modes, ear detection, volume swipe, press-and-hold behaviour,
and more, with a keyboard-driven Textual TUI.

Upstream targets Arch/Omarchy (`install.sh` + `PKGBUILD`). This repository is
the NixOS equivalent — but it is **not only for NixOS**: the flake exposes the
package and standalone apps, so you can run the whole thing without touching
any configuration.

```
┌─────────────┐   D-Bus    ┌─────────────┐   WebSocket    ┌──────────────────┐
│ BlueZ       │◄──────────►│ omarchpods  │◄──────────────►│ omarchpods-ui    │
│ (bluetoothd)│            │ core daemon │   localhost:   │ (Textual TUI)    │
└─────────────┘            │ (C++)       │   2020         └──────────────────┘
                           └─────────────┘
```

---

## Quick start — standalone, no NixOS needed

The only runtime requirement is a running BlueZ daemon (standard on any desktop
Linux). Then, from this repository:

```sh
# terminal 1: run the core daemon (foreground)
nix run .#omarchpods

# terminal 2: run the TUI (WebSocket connection to the daemon)
nix run .#ui
```

That's it. The daemon registers with BlueZ over D-Bus and serves a JSON
WebSocket API on `localhost:2020`; the TUI talks to it.

Other useful one-liners:

```sh
nix run .#omarchpods -- --version     # print version and exit
nix run .#launcher                    # open a terminal running the TUI
                                      #   (via xdg-terminal-exec, Omarchy-style)

nix build .#omarchpods                # build only
nix shell .#                          # drop into a shell with all three
                                      #   binaries on PATH
nix develop                           # dev shell: binaries + cmake, gcc,
                                      #   bluez headers, python (textual/pytest)
```

| `nix run .#…` | runs | notes |
| --- | --- | --- |
| *(default)* / `.#daemon` | `omarchpods` | core daemon, foreground |
| `.#ui` | `omarchpods-ui` | TUI in your current terminal |
| `.#launcher` | `omarchy-launch-omarchpods` | spawns a terminal running the TUI |

### Typical session

```sh
nix run .#omarchpods &      # daemon, logs to stdout
nix run .#ui                # UI in this terminal; Ctrl+C to quit
```

---

## Using it in a NixOS configuration

### Option A — flake module

```nix
# flake.nix
{
  inputs.omarchpods.url = "github:you/nixos-omarchpods";

  outputs = { nixpkgs, omarchpods, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        omarchpods.nixosModules.default
        { services.omarchpods.enable = true; }
      ];
    };
  };
}
```

### Option B — standalone module (no flakes)

```nix
# configuration.nix
{ ... }:
{
  imports = [ /path/to/nixos-omarchpods ];
  services.omarchpods.enable = true;
}
```

The module is fully self-contained: it builds the package from the pinned
revision in `versions.nix`, so no overlay is required. If `pkgs.omarchpods`
exists (e.g. via the overlay) it is used instead.

### Option C — overlay

```nix
let
  pkgs = import <nixpkgs> {
    overlays = [ (import /path/to/nixos-omarchpods/overlay.nix) ];
  };
in pkgs.omarchpods
```

### Module options

`services.omarchpods.*`

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Enable the core daemon (systemd user service) and, by default, the UI. |
| `package` | self-contained build | The omarchpods package to use. |
| `bluetooth.enable` | `true` | Enable BlueZ (`hardware.bluetooth`) and pull `bluetooth.target` into boot so `bluetoothd` actually starts. |
| `ui.enable` | `true` | Add the package (daemon + TUI launchers) to `environment.systemPackages`. |

With the module enabled, the daemon runs as the **systemd user service**
`omarchpods.service` (wanted by user `default.target`), matching upstream's
Omarchy packaging. Launch the TUI with `omarchpods-ui`, or bind a key:

```
# hyprland.conf
bind = SUPER SHIFT, H, exec, omarchy-launch-omarchpods
```

---

## What you get

| Binary | Description |
| --- | --- |
| `omarchpods` | The core daemon (`MagicPodsCore` C++). Owns the Bluetooth connection state and exposes a JSON WebSocket API on `localhost:2020`. |
| `omarchpods-ui` | The Python [Textual](https://textual.textualize.io/) TUI. |
| `omarchy-launch-omarchpods` | Opens a terminal running the TUI via `xdg-terminal-exec` (same behaviour as Omarchy's launcher). |

### WebSocket API (technical reference)

The daemon speaks JSON over WebSocket at `ws://localhost:2020`
(no authentication; local only). Requests:

```json
{ "method": "GetAll" }                                  // everything at once
{ "method": "GetDevices" }
{ "method": "GetActiveDeviceInfo" }
{ "method": "GetDefaultBluetoothAdapter" }
{ "method": "ConnectDevice",    "arguments": { "address": "AA:BB:CC:DD:EE:FF" } }
{ "method": "DisconnectDevice", "arguments": { "address": "AA:BB:CC:DD:EE:FF" } }
{ "method": "SetCapabilities",  "arguments": { "address": "...", "capabilities": { ... } } }
{ "method": "EnableDefaultBluetoothAdapter" }
{ "method": "DisableDefaultBluetoothAdapter" }
{ "method": "SetLogLevel",      "arguments": { "selected": 20 } }
```

`GetAll` responds with:

```json
{
  "headphones": [ { "name": "AirPods Pro", "address": "…", "connected": true, … } ],
  "defaultbluetooth": { "enabled": true },
  "info": { /* active device, including "capabilities" */ }
}
```

Broadcast topics (subscribe on connect): `onCapabilityChanged`,
`OnConnectedChanged`, `OnActiveDeviceChanged`, `OnDefaultAdapterChangeEnabled`.

---

## How it works

### The build (offline, reproducible)

Upstream's `CMakeLists.txt` downloads three dependencies at build time via CMake
FetchContent:

| dependency | version | used for |
| --- | --- | --- |
| [sdbus-cpp](https://github.com/Kistler-Group/sdbus-cpp) | v1.6.0 | D-Bus client (talks to BlueZ) |
| [uSockets](https://github.com/uNetworking/uSockets) | v0.8.7 | WebSocket networking |
| [uWebSockets](https://github.com/uNetworking/uWebSockets) | v20.58.0 | WebSocket server |

Nix builds are sandboxed (no network), so this derivation pre-fetches those
exact versions (`fetchFromGitHub`, pinned in `versions.nix`) and hands them to
CMake via `FETCHCONTENT_SOURCE_DIR_*` with `FETCHCONTENT_FULLY_DISCONNECTED=ON`.
The result: byte-for-byte reproducible, offline builds that never hit the
network — and the `dep-pins` check fails loudly if upstream bumps a version we
haven't.

Build inputs: `cmake`, `pkg-config`, `gcc` (stdenv), `git`, `zlib`,
`bluez` (libbluetooth headers), `systemdLibs` (libsystemd, required by
sdbus-cpp v1.6), plus `python3` with `textual`/`websocket-client` for the TUI.

Upstream ships no `install` rules, so the derivation places the artifacts
itself:

```
$out/bin/omarchpods                  ← build/MagicPodsCore
$out/bin/omarchpods-ui               ← wrapper: python ui/main.py (PYTHONPATH set)
$out/bin/omarchy-launch-omarchpods   ← wrapper: xdg-terminal-exec … python ui/main.py
$out/share/omarchpods/ui             ← the Textual TUI sources
```

The TUI's volume control shells out to `pactl`; both wrappers therefore add
`pulseaudio` to `PATH` so it works on a bare NixOS without PulseAudio/PipeWire
in your profile.

### The systemd user service

```ini
# ~/.config/systemd/user/omarchpods.service (generated by the module)
[Unit]
After=bluetooth.target
Wants=bluetooth.target

[Service]
Type=simple
ExecStart=/nix/store/…-omarchpods/bin/omarchpods
Restart=on-failure
RestartSec=5
```

The module also wires `hardware.bluetooth.enable` and makes `bluetooth.target`
reach boot, because on minimal NixOS systems nothing else pulls it in.

### Patches (local changes vs upstream)

Two small, documented fixes are applied on top of upstream:

1. **`patches/tolerate-missing-bluez.patch`** — upstream's
   `DBusService::GetBtDevices()` is not exception-safe. When `org.bluez` is
   unavailable (no adapter, or D-Bus activation fails — e.g. bluetoothd's unit
   condition `ConditionPathIsDirectory=/sys/class/bluetooth` is unmet in a VM)
   the uncaught `sdbus::Error` terminates the daemon with SIGABRT. The patch
   wraps the call in try/catch, matching the constructor's existing defensive
   style, and treats "no BlueZ" as "no devices". Verified: the daemon serves
   `GetAll` with an empty device list when BlueZ is down.
2. **TUI runtime PATH** — see above (`pactl`).

If upstream ever fixes these, the patch application fails loudly and you can
drop them from the derivation.

---

## Tests

```sh
nix flake check
```

All checks are offline/sandbox-safe (nothing needs network access) and run per
supported system (`x86_64-linux`, `aarch64-linux`):

| Check | What it does |
| --- | --- |
| `build` | Full package build from source (C++ core + TUI wrappers). |
| `ui-tests` | Runs upstream's 78 pytest cases against the packaged UI. |
| `dep-pins` | Fails if the FetchContent pins in `versions.nix` no longer match what the pinned upstream source declares. |
| `nixos-test` | Boots a NixOS VM with the module enabled; asserts the unit file; starts the **user** service under a real login session (getty autologin); queries the WebSocket API with and without BlueZ; launches the TUI headless without crashing. Uses the standalone `default.nix` entry point. |

Run a single check:

```sh
nix build .#checks.x86_64-linux.ui-tests
nix build .#checks.x86_64-linux.nixos-test   # VM test (slowest)
```

---

## Updating

Upstream moves fast; `versions.nix` pins a specific commit of the `master`
branch. Refresh it with:

```sh
./update.sh              # bump to latest upstream master, then run nix flake check
./update.sh some-branch  # track a different branch
./update.sh --check      # report drift without changing anything (exit 1 if behind)
```

What the script does:

1. queries the GitHub API for the branch head commit,
2. updates `rev` + matching `sha256` in `versions.nix`,
3. compares our FetchContent pins with what the *new* source declares and warns
   on drift (the `dep-pins` check will then fail until you bump `versions.nix`),
4. re-locks the `nixpkgs` input and runs `nix flake check` so you commit a
   known-good state.

You can also point the package at any source yourself:

```nix
{ config, pkgs, ... }: {
  services.omarchpods.package = pkgs.callPackage ./nixos-omarchpods/packages/omarchpods.nix {
    sourceInput = pkgs.fetchFromGitHub {
      owner = "tomycostantino"; repo = "omarchpods";
      rev = "…"; sha256 = "…";
    };
  };
}
```

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Failed to connect to server` in the TUI | Core daemon isn't running — start it (`nix run .#omarchpods`, or the user service), then wait for `Listening on port 2020`. |
| No devices in the TUI | Check `bluetoothctl` sees paired devices and the adapter is powered. The daemon only lists paired headphones it recognises (see the supported-devices list upstream). |
| `WRN Failed to get managed objects: Could not activate remote peer 'org.bluez'` | BlueZ isn't running. With the NixOS module this is wired up; standalone, start it (`systemctl start bluetooth` or your distro's equivalent). The daemon no longer crashes in this state (see Patches). |
| Volume slider does nothing | The UI needs `pactl` talking to a running PulseAudio/PipeWire — our wrappers provide `pactl`, the audio server is up to you. |
| Service keeps restarting | `journalctl --user -u omarchpods.service -f` for the core daemon log. The TUI writes its own log to `/tmp/omarchpods.log`. |

---

## Development

```sh
nix develop        # binaries + cmake, gcc, bluez headers, libsystemd, python
nix fmt            # nixpkgs-fmt over the repo
```

Iterating on the C++ core? The dev shell has everything `cmake` needs. To compile
upstream sources by hand, pre-fetch the three FetchContent dependencies exactly as
the derivation does and point CMake at them (see `packages/omarchpods.nix` and
`versions.nix` — the derivation is the reference implementation):

```sh
nix develop --command bash -c '\
  cmake -B build -DCMAKE_BUILD_TYPE=Debug \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DFETCHCONTENT_SOURCE_DIR_SDBUS-CPP=<sdbus-cpp-v1.6.0-src> \
    -DFETCHCONTENT_SOURCE_DIR_USOCKETS_CONTENT=<usockets-v0.8.7-src> \
    -DFETCHCONTENT_SOURCE_DIR_UWEBSOCKETS_CONTENT=<uwebsockets-v20.58.0-src> \
  && cmake --build build'
```

(Or just add the pre-fetched FetchContent deps from `versions.nix` the same way
the derivation does.)

## Repository layout

```
flake.nix                # packages, apps, module, overlay, checks, devShell, formatter
default.nix              # standalone module entry point (imports = [ <this repo> ])
modules/default.nix      # the actual NixOS module
packages/omarchpods.nix  # package derivation (offline FetchContent, wrappers, patch)
versions.nix             # pinned upstream rev + dependency pins (managed by update.sh)
patches/                 # local patches applied to upstream
tests/                   # ui-tests, dep-pins, nixos-test
update.sh                # track the upstream branch
overlay.nix              # pkgs.omarchpods overlay
```

## License

GPL-3.0, matching upstream omarchpods / MagicPodsCore.
