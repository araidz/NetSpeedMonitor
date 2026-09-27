#!/usr/bin/env bash
#
# Build, tag, and publish a GitHub release locally, then update Homebrew.
#
#   ./release.sh 1.6
#
# Bump MARKETING_VERSION in the Xcode project first; this only ships it.
set -euo pipefail
cd "$(dirname "$0")"

version="${1:?usage: ./release.sh <version>}"
name="netspeedmonitor"
tag="v$version"
tap="../homebrew-tap"
build_dir="build/Release"

for tool in gh xcodebuild git shasum lipo codesign ditto; do
  command -v "$tool" >/dev/null || { echo "✗ required command not found: $tool" >&2; exit 1; }
done
gh auth status >/dev/null

branch="$(git symbolic-ref --quiet --short HEAD)" || { echo "✗ not on a branch" >&2; exit 1; }
[ "$branch" = main ] || { echo "✗ current branch must be main (found $branch)" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=all)" ] || { echo "✗ working tree must be clean" >&2; exit 1; }

git fetch origin main --tags
git push origin main

project_version="$(xcodebuild -project NetSpeedMonitor.xcodeproj -scheme NetSpeedMonitor \
  -configuration Release -showBuildSettings | awk '$1 == "MARKETING_VERSION" && !v { v=$3 } END { print v }')"
[ "$project_version" = "$version" ] \
  || { echo "✗ MARKETING_VERSION is $project_version, expected $version — bump it in the project first" >&2; exit 1; }

echo "▸ building universal release…"
rm -rf "$build_dir"
xcodebuild \
  -project NetSpeedMonitor.xcodeproj \
  -scheme NetSpeedMonitor \
  -configuration Release \
  ARCHS="x86_64 arm64" \
  ONLY_ACTIVE_ARCH=NO \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CONFIGURATION_BUILD_DIR="$build_dir" \
  clean build

app="$build_dir/NetSpeedMonitor.app"
executable="$app/Contents/MacOS/NetSpeedMonitor"
architectures=" $(lipo -archs "$executable") "
[[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] \
  || { echo "✗ built executable is not universal arm64/x86_64" >&2; exit 1; }

xattr -cr "$app"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$app/Contents/Info.plist"
codesign --force --deep --sign - --options=runtime --timestamp "$app"
codesign --verify --deep --strict "$app"

( cd "$build_dir" && ditto -c -k --keepParent NetSpeedMonitor.app NetSpeedMonitor.zip \
  && shasum -a 256 NetSpeedMonitor.zip > NetSpeedMonitor.sha256 )

git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git tag -a "$tag" -m "NetSpeedMonitor $tag"
git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1 || git push origin "$tag"
gh release view "$tag" >/dev/null 2>&1 || gh release create "$tag" \
  "$build_dir/NetSpeedMonitor.zip" "$build_dir/NetSpeedMonitor.sha256" \
  --title "NetSpeedMonitor $tag" --generate-notes

if [ -f "$tap/Formula/$name.rb" ] || [ -f "$tap/Casks/$name.rb" ]; then
  "$tap/bump.sh" "$name" "$version"
else
  echo "△ no Homebrew entry for $name — skipping tap bump"
fi
echo "✓ released NetSpeedMonitor $tag"
