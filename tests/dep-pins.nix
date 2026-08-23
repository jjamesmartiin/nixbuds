# Verifies that the FetchContent dependency versions pinned in versions.nix
# still match what the upstream repo's dependencies/*/CMakeLists.txt request.
# Upstream bumps these from time to time; when they do, run ./update.sh (or
# bump versions.nix by hand) until this check passes again.
{ pkgs, lib, versions ? import ../versions.nix }:

let
  src = pkgs.fetchFromGitHub {
    owner = versions.owner;
    repo = versions.repo;
    rev = versions.rev;
    sha256 = versions.sha256;
  };

  # dir -> versions.nix attr
  deps = [
    { dir = "sdbus-cpp"; attr = "sdbus-cpp"; }
    { dir = "uSockets"; attr = "uSockets"; }
    { dir = "uWebSockets"; attr = "uWebSockets"; }
  ];

  checkPhase = lib.concatMapStringsSep "\n"
    (dep:
      let version = versions.deps.${dep.attr}.version; in
      ''
        if ! grep -q "${version}" "dependencies/${dep.dir}/CMakeLists.txt"; then
          echo
          echo "ERROR: dependencies/${dep.dir}/CMakeLists.txt no longer pins ${version}"
          echo "       (pinned in versions.nix). Upstream changed the version -"
          echo "       run ./update.sh or update versions.nix."
          echo
          exit 1
        fi
        echo "OK: dependencies/${dep.dir} still pins ${version}"
      '')
    deps;
in
pkgs.stdenv.mkDerivation {
  name = "omarchpods-dep-pin-check";
  inherit src;

  doCheck = true;
  inherit checkPhase;

  installPhase = ''
    mkdir -p "$out"
  '';

  meta = {
    description = "Checks that versions.nix dependency pins match upstream";
    platforms = lib.platforms.linux;
  };
}
