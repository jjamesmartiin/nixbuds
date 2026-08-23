# Omarchpods — a Nix build of https://github.com/tomycostantino/omarchpods
# (a fork of MagicPodsCore with a TUI, designed for Omarchy).
#
# The derivation builds the C++ core ("MagicPodsCore", a Bluetooth headphone
# daemon that talks to BlueZ over D-Bus and exposes a WebSocket API on
# localhost:2020) and packages the Python Textual TUI that talks to it.
#
# Upstream's CMakeLists.txt expects to download three dependencies at build
# time via FetchContent (sdbus-cpp, uSockets, uWebSockets). Nix builds are
# offline, so we pre-fetch those exact versions and point FetchContent at the
# local copies. This keeps the build fully sandboxed and reproducible.
{ lib
, stdenv
, fetchFromGitHub
, cmake
, pkg-config
, git
, makeWrapper
, zlib
, bluez
, systemdLibs
, python3
, xdg-terminal-exec
, pulseaudio
, versions ? import ../versions.nix
  # Allow callers (e.g. the flake) to pass their own source; defaults to the
  # pinned revision in versions.nix so the package is self-contained.
, sourceInput ? null
}:

let
  source = if sourceInput != null then sourceInput else
  fetchFromGitHub {
    owner = versions.owner;
    repo = versions.repo;
    rev = versions.rev;
    sha256 = versions.sha256;
  };

  # FetchContent dependencies pinned in versions.nix, pre-fetched so the Nix
  # sandbox never needs network access.
  ownerOf = url: builtins.elemAt (builtins.match "https://github.com/([^/]+)/.*" url) 0;

  sdbus-cpp = fetchFromGitHub {
    owner = ownerOf versions.deps.sdbus-cpp.url;
    repo = "sdbus-cpp";
    rev = versions.deps.sdbus-cpp.version;
    sha256 = versions.deps.sdbus-cpp.sha256;
  };
  uSockets = fetchFromGitHub {
    owner = ownerOf versions.deps.uSockets.url;
    repo = "uSockets";
    rev = versions.deps.uSockets.version;
    sha256 = versions.deps.uSockets.sha256;
  };
  uWebSockets = fetchFromGitHub {
    owner = ownerOf versions.deps.uWebSockets.url;
    repo = "uWebSockets";
    rev = versions.deps.uWebSockets.version;
    sha256 = versions.deps.uWebSockets.sha256;
  };

  python = python3.withPackages (ps: [ ps.textual ps.websocket-client ]);

  version = builtins.substring 0 10 versions.rev;
in
stdenv.mkDerivation {
  pname = "omarchpods";
  inherit version;

  src = source;

  nativeBuildInputs = [ cmake pkg-config git makeWrapper ];
  buildInputs = [ zlib bluez systemdLibs.dev ];

  # Upstream crashes (SIGABRT) at startup when org.bluez is unavailable or its
  # D-Bus activation fails, because GetBtDevices() is not exception-safe.
  # See patches/tolerate-missing-bluez.patch for details.
  patches = [
    ./../patches/tolerate-missing-bluez.patch
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    # Do not let CMake go to the network during the build.
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
    "-DFETCHCONTENT_UPDATES_DISCONNECTED=ON"
    # Point the vendored FetchContent declarations at pre-fetched sources.
    "-DFETCHCONTENT_SOURCE_DIR_SDBUS-CPP=${sdbus-cpp}"
    "-DFETCHCONTENT_SOURCE_DIR_USOCKETS_CONTENT=${uSockets}"
    "-DFETCHCONTENT_SOURCE_DIR_UWEBSOCKETS_CONTENT=${uWebSockets}"
  ];

  # Upstream ships no install rules, so we place the artifacts ourselves.
  # (The cmake builder compiles out-of-source: binaries land in build/,
  # the unpacked source tree is in source/.)
  installPhase = ''
    runHook preInstall

    install -Dm755 MagicPodsCore "$out/bin/omarchpods"
    mkdir -p "$out/share/omarchpods"
    cp -r ../ui "$out/share/omarchpods/ui"

    # Plain launcher: run the TUI in the current terminal.
    makeWrapper "${python}/bin/python" "$out/bin/omarchpods-ui" \
      --set PYTHONPATH "$out/share/omarchpods/ui" \
      --prefix PATH : "${lib.makeBinPath [ pulseaudio ]}" \
      --add-flags "$out/share/omarchpods/ui/main.py"

    # Omarchy-style launcher: open a terminal running the TUI.
    makeWrapper "${xdg-terminal-exec}/bin/xdg-terminal-exec" \
      "$out/bin/omarchy-launch-omarchpods" \
      --prefix PATH : "${lib.makeBinPath [ pulseaudio ]}" \
      --add-flags "--app-id=com.omarchy.Omarchy --title=Omarchpods" \
      --add-flags "${python}/bin/python $out/share/omarchpods/ui/main.py"

    runHook postInstall
  '';

  meta = {
    description = "Headphones integration (AirPods / Galaxy Buds / Beats) with a Textual TUI, forked from MagicPodsCore for Omarchy";
    homepage = "https://github.com/tomycostantino/omarchpods";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
    platforms = lib.platforms.linux;
    mainProgram = "omarchpods";
  };
}
