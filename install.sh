#!/usr/bin/env bash
# Installs (or updates to) a universal agterm build from this repo's releases.
# usage: install.sh [tag]   e.g. v0.33.1 or v0.33.1-universal; no tag = latest release
set -euo pipefail

repo="parMaster/agterm-universal"
app="/Applications/agterm.app"

die() {
  echo "error: $*" >&2
  exit 1
}

tag="${1:-}"
if [ -z "$tag" ]; then
  # the redirect target carries the tag; the REST API would rate-limit anonymous callers
  latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")" ||
    die "could not look up the latest release of $repo"
  tag="${latest_url##*/}"
  [[ "$tag" == *-universal ]] || die "could not read a release tag from $latest_url"
fi
tag="${tag%-universal}-universal"
url="https://github.com/$repo/releases/download/$tag/agterm-$tag.zip"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
echo "work directory: $workdir"

echo "downloading $url"
curl -fsSL -o "$workdir/agterm.zip" "$url" || die "no release $tag in $repo (tried $url)"
unzip -q "$workdir/agterm.zip" -d "$workdir"
new_app="$workdir/agterm.app"
[ -d "$new_app" ] || die "the zip for $tag has no agterm.app in it"

# checked before anything installed is touched, so a bad download leaves the working app alone
archs="$(lipo -archs "$new_app/Contents/MacOS/agterm")"
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || die "$tag is not a universal build (archs: $archs)"

have_brew=0
if command -v brew >/dev/null 2>&1; then
  have_brew=1
  # never --zap: it deletes ~/Library/Application Support/agterm, breaking a running instance's control socket
  if brew list --cask agterm >/dev/null 2>&1; then
    echo "removing the Homebrew agterm cask"
    brew uninstall --cask agterm
  fi
fi

rm -rf "$app"
mv "$new_app" "$app"
# the build is ad-hoc signed, not notarized; Gatekeeper blocks it if a quarantine flag is present
xattr -cr "$app"

echo "installed $tag to $app"
echo "archs: $(lipo -archs "$app/Contents/MacOS/agterm")"
codesign -dv "$app" 2>&1 | grep -E '^(Signature|TeamIdentifier)=' || true

if [ "$have_brew" = 1 ]; then
  link="$(brew --prefix)/bin/agtermctl"
  ln -sf "$app/Contents/MacOS/agtermctl" "$link"
  "$link" --help >/dev/null || die "$link does not run"
  echo "agtermctl: $link"
else
  echo "Homebrew not found, so agtermctl was not put on PATH. To do it yourself:"
  echo "  ln -sf $app/Contents/MacOS/agtermctl <a directory on your PATH>/agtermctl"
fi

echo "A running agterm keeps the old version until you quit and reopen it."
