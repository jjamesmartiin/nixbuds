#!/usr/bin/env bash
# Update the pinned upstream revision of omarchpods.
#
#   ./update.sh            update to the latest commit on the upstream master branch
#   ./update.sh <branch>   update to the latest commit on a different branch
#   ./update.sh --check    report whether the pinned revision matches the branch
#                          head; exit 1 if there is drift (does not modify anything)
#
# The script:
#   1. asks the GitHub API for the branch head commit,
#   2. updates `rev` (and the matching `sha256`) in versions.nix,
#   3. warns when the FetchContent dependency pins in versions.nix no longer
#      match what the new source declares (the `dep-pins` check enforces it),
#   4. re-locks the nixpkgs input and runs `nix flake check` to make sure
#      everything still builds and tests pass.
set -euo pipefail

cd "$(dirname "$0")"

REPO="tomycostantino/omarchpods"
VERSIONS="versions.nix"

if ! command -v curl >/dev/null; then
  echo "error: curl is required" >&2
  exit 1
fi
if ! command -v nix >/dev/null; then
  echo "error: nix is required" >&2
  exit 1
fi

MODE="update"
BRANCH="master"
if [ "${1:-}" = "--check" ]; then
  MODE="check"
elif [ -n "${1:-}" ]; then
  BRANCH="$1"
fi

current_rev="$(sed -n 's/^  rev = "\([0-9a-f]*\)";.*/\1/p' "$VERSIONS" | head -1)"
owner="$(sed -n 's/^  owner = "\([^"]*\)";.*/\1/p' "$VERSIONS" | head -1)"
repo="$(sed -n 's/^  repo = "\([^"]*\)";.*/\1/p' "$VERSIONS" | head -1)"

echo "==> Querying https://github.com/$owner/$repo branch '$BRANCH' ..."
api="https://api.github.com/repos/$owner/$repo/commits/$BRANCH"
latest_sha="$(curl -fsSL "$api" | grep -oP '"sha":\s*"\K[0-9a-f]{40}' | head -1)"
if [ -z "$latest_sha" ]; then
  echo "error: could not determine the head commit of branch '$BRANCH'" >&2
  exit 1
fi

if [ "$latest_sha" = "$current_rev" ]; then
  echo "==> Already up to date (pinned at $current_rev)."
else
  echo "==> Upstream head is $latest_sha (pinned: $current_rev)."
  if [ "$MODE" = "check" ]; then
    echo "!!! versions.nix is behind the $BRANCH branch — run ./update.sh"
    exit 1
  fi

  echo "==> Fetching new source hash ..."
  tarball="https://github.com/$owner/$repo/archive/$latest_sha.tar.gz"
  sha256="$(nix store prefetch-file --unpack --json "$tarball" \
    | grep -oP '"hash":\s*"\K[^"]+' | head -1)"
  if [ -z "$sha256" ]; then
    echo "error: could not compute the source hash" >&2
    exit 1
  fi

  sed -i "s|^  rev = \"$current_rev\";|  rev = \"$latest_sha\";|" "$VERSIONS"
  sed -i "s|^  sha256 = \"[^\"]*\";|  sha256 = \"$sha256\";|" "$VERSIONS"
  echo "==> versions.nix: $current_rev -> $latest_sha"
  echo "    sha256: $sha256"
fi

# Warn about FetchContent dependency drift (the `dep-pins` check enforces it).
echo "==> Comparing FetchContent dependency pins ..."
ok=1
for dep in sdbus-cpp uSockets uWebSockets; do
  pinned="$(sed -n "/$dep = {/,/};/ s/^      version = \"\([^\"]*\)\".*/\1/p" "$VERSIONS" | head -1)"
  upstream="$(curl -fsSL "https://raw.githubusercontent.com/$owner/$repo/$latest_sha/dependencies/$dep/CMakeLists.txt" \
    | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [ -n "$upstream" ] && [ "$pinned" != "$upstream" ]; then
    echo "    WARN: $dep upstream now pins '$upstream' but versions.nix has '$pinned'"
    ok=0
  else
    echo "    ok: $dep $pinned"
  fi
done
if [ "$ok" = "0" ]; then
  echo "!!! Update the $dep pins in versions.nix (or run the dep-pins check to confirm)."
fi

if [ "$MODE" = "update" ]; then
  echo "==> Re-locking nixpkgs input ..."
  nix flake lock --update-input nixpkgs >/dev/null

  echo "==> Running 'nix flake check' ..."
  nix flake check

  echo
  echo "Done. Commit the changes:"
  echo "    git add versions.nix flake.lock && git commit"
fi
