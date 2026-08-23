# nixos-omarchpods

NixOS packaging for [omarchpods](https://github.com/tomycostantino/omarchpods) —
a fork of [MagicPodsCore](https://github.com/steam3d/MagicPodsCore) that gives
you a Bluetooth headphone daemon plus a Textual TUI for managing AirPods,
Galaxy Buds and Beats on Linux.

The upstream project targets Arch/Omarchy (`install.sh` + `PKGBUILD`). This
repository is the NixOS equivalent: a self-contained package, a NixOS module,
a flake with automated tests, and an update script that tracks the upstream
`master` branch.

## What you get

| Artifact | Description |
| --- | --- |
| `omarchpods` | The C++ core daemon. Talks to BlueZ over D-Bus and exposes a WebSocket API on `localhost:2020` (same as MagicPodsCore). |
| `omarchpods-ui` | The Textual TUI, run in your current terminal. |
| `omarchy-launch-omarchpods` | Omarchy-style launcher: opens a terminal (via `xdg-terminal-exec`) running the TUI. |

Plus a `systemd` **user** service that runs the core daemon on login, matching
upstream's `omarchpods.service`.

## Usage

### 1. As a flake module (recommended)

```nix
# flake.nix
{
  inputs.omarchpods.url = "github:you/nixos-omarchpods";

  outputs = { nixpkgs, omarchpods, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        omarchpods.nixosModules.default
        {
          services.omarchpods.enable = true;
        }
      ];
    };
  };
}
```

### 2. As a standalone module (no flakes)

```nix
# configuration.nix
{ ... }:
{
  imports = [ /path/to/nixos-omarchpods ];
  services.omarchpods.enable = true;
}
```

The module is fully self-contained — it builds the package from the pinned
revision in `versions.nix`, so you don't need an overlay. (If `pkgs.omarchpods`
exists, e.g. via the overlay, it is used instead.)

### 3. Just the package / overlay

```nix
# flake.nix
{
  inputs.omarchpods.url = "github:you/nixos-omarchpods";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, omarchpods, ... }: {
    packages.x86_64-linux.default = omarchpods.packages.x86_64-linux.default;
  };
}
```

```sh
nix build .#omarchpods            # build the package
nix run .#omarchpods -- --version # print version
```

Or use the overlay in a plain nixpkgs setup:

```nix
let
  pkgs = import <nixpkgs> {
    overlays = [ (import /path/to/nixos-omarchpods/overlay.nix) ];
  };
in pkgs.omarchpods
```

## Options

`services.omarchpods.*`

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Enable the core daemon service + (by default) the UI. |
| `package` | self-contained build | The omarchpods package to use. |
| `bluetooth.enable` | `true` | Enable BlueZ (`hardware.bluetooth`) and make `bluetooth.target` reach boot so `bluetoothd` actually starts. |
| `ui.enable` | `true` | Add the package (daemon + TUI launchers) to `environment.systemPackages`. |

The daemon is installed as a `systemd` user service (`omarchpods.service`,
wanted by user `default.target`), exactly like upstream's Omarchy packaging.
Launch the TUI with `omarchpods-ui` or bind `omarchy-launch-omarchpods` to a
Hyprland key, e.g.:

```
bind = SUPER SHIFT, H, exec, omarchy-launch-omarchpods
```

## Tests

```sh
nix flake check
```

Runs (per supported system):

| Check | What it does |
| --- | --- |
| `build` | Builds the full package from source (C++ core + TUI). |
| `ui-tests` | Runs upstream's 78 pytest cases against the packaged UI. |
| `dep-pins` | Fails if the FetchContent dependency pins in `versions.nix` no longer match what the pinned upstream source declares. |
| `nixos-test` | Boots a NixOS VM with the module enabled; starts the user service under a real login session; queries the WebSocket API (with and without BlueZ); launches the TUI headless. |

The tests are intentionally offline/sandbox-safe — nothing in `nix flake check`
needs network access.

## Updating

Upstream moves fast, so `versions.nix` pins a specific commit of the `master`
branch. Update it with:

```sh
./update.sh            # bump to the latest upstream master, then run nix flake check
./update.sh some-branch # track a different branch
./update.sh --check    # report drift without changing anything (exit 1 if behind)
```

The script also warns when the dependency versions upstream pins in its
`dependencies/*/CMakeLists.txt` no longer match ours (the `dep-pins` check will
then fail until you bump `versions.nix`).

You can also point the package at any source yourself:

```nix
{ config, pkgs, ... }: {
  services.omarchpods.package = pkgs.callPackage ./nixos-omarchpods/packages/omarchpods.nix {
    sourceInput = pkgs.fetchFromGitHub { /* your own rev */ };
  };
}
```

## Patches (local changes vs upstream)

Two small, documented fixes are applied on top of upstream:

1. **`patches/tolerate-missing-bluez.patch`** — upstream's
   `DBusService::GetBtDevices()` is not exception-safe: when `org.bluez` is
   unavailable (no adapter, or D-Bus activation fails) the uncaught
   `sdbus::Error` terminates the daemon with SIGABRT. The patch wraps the call
   in try/catch (matching the constructor's existing defensive style) and
   treats "no BlueZ" as "no devices".
2. **TUI runtime PATH** — the volume control needs `pactl`; the `omarchpods-ui`
   and `omarchy-launch-omarchpods` wrappers add `pulseaudio` to `PATH` so the
   UI works out of the box on NixOS.

If upstream fixes these, the patch application (or the tests) will fail loudly
and you can drop them.

## Development

```sh
nix develop        # cmake, gcc, bluez headers, sdbus, python (textual/pytest) etc.
nix fmt            # format with nixpkgs-fmt
```

## Layout

```
flake.nix                # packages, module, overlay, checks, devShell
default.nix              # standalone module entry point (imports = [ <this repo> ])
modules/default.nix      # the actual NixOS module
packages/omarchpods.nix  # package derivation (offline FetchContent via versions.nix)
versions.nix             # pinned upstream rev + dependency versions (managed by update.sh)
patches/                 # local patches applied to upstream
tests/                   # ui-tests, dep-pins, nixos-test
update.sh                # track the upstream branch
overlay.nix              # pkgs.omarchpods overlay
```

## License

Upstream omarchpods/MagicPodsCore is GPL-3.0; this repository is GPL-3.0 too.
