# Runs the upstream UI test-suite (pytest) against our packaged UI
# dependencies. This keeps the Textual TUI working as upstream evolves.
{ pkgs, lib, versions ? import ../versions.nix }:

let
  src = pkgs.fetchFromGitHub {
    owner = versions.owner;
    repo = versions.repo;
    rev = versions.rev;
    sha256 = versions.sha256;
  };

  python = pkgs.python3.withPackages (ps: [
    ps.textual
    ps.websocket-client
    ps.pytest
  ]);
in
pkgs.stdenv.mkDerivation {
  name = "omarchpods-ui-tests";
  inherit src;

  nativeBuildInputs = [ python ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    cd ui
    export HOME="$TMPDIR"
    python -m pytest --tb=short
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    runHook postInstall
  '';

  meta = {
    description = "Automated tests for the omarchpods Textual UI";
    platforms = lib.platforms.linux;
  };
}
