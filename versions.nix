# Source pins for the omarchpods build.
#
# This file is maintained by ./update.sh — do not edit by hand unless you
# know what you are doing. `nix flake check` (or the `update-check` test)
# verifies that the pinned revision here matches the one on the upstream
# `master` branch, so the build always tracks whatever upstream is doing.
{
  # Upstream repository / branch this package tracks.
  owner = "tomycostantino";
  repo = "omarchpods";
  branch = "master";

  # Full commit SHA of the upstream branch (see update.sh).
  rev = "575094b516ec3fa1433f81fd1809c9ed67f272fe";

  # SRI hash of the unpacked tarball of the above revision.
  sha256 = "sha256-TaOrFbUwxTrgZg7fEw+OLJY5qtTleK72/vw0b7zUWIs=";

  # Build-time dependencies that upstream pulls in via CMake FetchContent.
  # update.sh warns if these stop matching what upstream pins.
  deps = {
    sdbus-cpp = {
      version = "v1.6.0";
      url = "https://github.com/Kistler-Group/sdbus-cpp/archive/refs/tags/v1.6.0.tar.gz";
      sha256 = "sha256-h4eSVBm5VO5ol883dFKoilVGAcQVANNbFFVxKib2D48=";
    };
    uSockets = {
      version = "v0.8.7";
      url = "https://github.com/uNetworking/uSockets/archive/refs/tags/v0.8.7.tar.gz";
      sha256 = "sha256-vf3xI5GOqTEZx8iXf133nQvhUylIRzJ3jGuNUcQk9nY=";
    };
    uWebSockets = {
      version = "v20.58.0";
      url = "https://github.com/uNetworking/uWebSockets/archive/refs/tags/v20.58.0.tar.gz";
      sha256 = "sha256-XSyX6iP+wlUcmBMdfvNyf/uFCzQGmogIS5ehUnRdWs0=";
    };
  };
}
