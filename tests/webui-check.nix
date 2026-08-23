# Sanity checks for the web UI sources (this repo's own code, not upstream):
#   - app.js must be valid JavaScript (node --check)
#   - index.html must reference the stylesheet and the app
#   - every referenced asset must exist
{ pkgs, lib }:

let
  webui = ../webui;
in
pkgs.stdenv.mkDerivation {
  name = "omarchpods-webui-check";
  src = webui;

  nativeBuildInputs = [ pkgs.nodejs ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    echo "==> node --check app.js"
    node --check app.js

    echo "==> index.html references"
    for ref in styles.css app.js; do
      if ! grep -q "$ref" index.html; then
        echo "ERROR: index.html does not reference $ref" >&2
        exit 1
      fi
      if [ ! -f "$ref" ]; then
        echo "ERROR: referenced file $ref is missing" >&2
        exit 1
      fi
    done

    # The page must talk to the daemon's WebSocket endpoint.
    if ! grep -q "ws://localhost:2020" app.js; then
      echo "ERROR: app.js does not reference the daemon WebSocket endpoint" >&2
      exit 1
    fi

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    runHook postInstall
  '';

  meta = {
    description = "Static checks for the omarchpods web UI";
    platforms = lib.platforms.linux;
  };
}
