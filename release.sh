#!/usr/bin/env bash
#
# Tag, let GitHub Actions build the universal .zip, publish the draft it creates,
# then update the Homebrew cask.
#
#   ./release.sh <version>      e.g. ./release.sh 1.5
#
# Building happens in CI (.github/workflows/auto_build.yaml) on the tag push;
# this waits for the drafted release, publishes it, then bumps the tap.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "usage: ./release.sh 1.5" >&2
  exit 1
fi

version="$1"
tap="../homebrew-tap"
tag="v$version"

for tool in gh xcodebuild git shasum unzip lipo codesign; do
  command -v "$tool" >/dev/null || { echo "✗ required command not found: $tool" >&2; exit 1; }
done
gh auth status >/dev/null

[[ -d "$tap/.git" ]] || { echo "✗ Homebrew tap not found at $tap" >&2; exit 1; }
[[ -x "$tap/bump.sh" ]] || { echo "✗ missing executable $tap/bump.sh" >&2; exit 1; }

[[ -z "$(git status --porcelain --untracked-files=all)" ]] \
  || { echo "✗ working tree must be clean" >&2; exit 1; }
git fetch origin main --tags
[[ "$(git branch --show-current)" == main ]] \
  || { echo "✗ releases must be run from main" >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || { echo "✗ local HEAD must equal origin/main" >&2; exit 1; }

git -C "$tap" fetch origin main
[[ -z "$(git -C "$tap" status --porcelain --untracked-files=all)" ]] \
  || { echo "✗ Homebrew tap working tree must be clean" >&2; exit 1; }
[[ "$(git -C "$tap" branch --show-current)" == main ]] \
  || { echo "✗ Homebrew tap must be on main" >&2; exit 1; }
# bump.sh strictly validates a local commit left behind by a failed push.
read -r tap_behind tap_ahead < <(git -C "$tap" rev-list --left-right --count origin/main...HEAD)
[[ "$tap_behind" -eq 0 ]] \
  || { echo "✗ Homebrew tap main is behind or diverged from origin/main" >&2; exit 1; }

project_version="$(xcodebuild -project "NetSpeedMonitor.xcodeproj" -scheme "NetSpeedMonitor" \
  -configuration Release -showBuildSettings | awk '$1 == "MARKETING_VERSION" && !version { version=$3 } END { print version }')"
[[ "$project_version" == "$version" ]] \
  || { echo "✗ MARKETING_VERSION is $project_version, expected $version" >&2; exit 1; }

head="$(git rev-parse HEAD)"
local_tag=""
if git show-ref --verify --quiet "refs/tags/$tag"; then
  local_tag="$(git rev-list -n 1 "$tag")"
  [[ "$local_tag" == "$head" ]] \
    || { echo "✗ local tag $tag points to $local_tag, expected $head" >&2; exit 1; }
fi
remote_tag="$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}" | \
  awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 } END { print peeled ? peeled : direct }')"
[[ -z "$remote_tag" || "$remote_tag" == "$head" ]] \
  || { echo "✗ remote tag $tag points to $remote_tag, expected $head" >&2; exit 1; }

[[ -n "$local_tag" ]] || git tag "$tag"
[[ -n "$remote_tag" ]] || git push origin "$tag"

echo "▸ waiting for CI to build and draft $tag…"
release_ready=false
release_state=""
for _ in $(seq 1 60); do
  if release_info="$(gh release view "$tag" --json assets,isDraft,isPrerelease -q \
    '[(if .isPrerelease then "prerelease" elif .isDraft then "draft" else "public" end), (([.assets[].name] | index("NetSpeedMonitor.zip")) != null and ([.assets[].name] | index("NetSpeedMonitor.sha256")) != null)] | @tsv' 2>/dev/null)"; then
    IFS=$'\t' read -r release_state assets_ready <<< "$release_info"
    [[ "$release_state" != prerelease ]] \
      || { echo "✗ unexpected prerelease state for $tag" >&2; exit 1; }
    if [[ "$assets_ready" == true ]]; then
      release_ready=true
      break
    fi
  fi
  run_state="$(gh run list --workflow auto_build.yaml --branch "$tag" --event push --limit 1 \
    --json status,conclusion -q '.[0] | if . == null then "" else "\(.status) \(.conclusion // "")" end')"
  case "$run_state" in
    ""|queued\ *|in_progress\ *|pending\ *|requested\ *|waiting\ *|completed\ success) ;;
    completed\ *) echo "✗ release workflow failed: $run_state" >&2; exit 1 ;;
    *) echo "✗ unexpected release workflow state: $run_state" >&2; exit 1 ;;
  esac
  sleep 15
done
[[ "$release_ready" == true ]] \
  || { echo "✗ CI ZIP and SHA256 assets not found — check the Actions run" >&2; exit 1; }

verification_dir="$(mktemp -d)"
trap 'rm -rf "$verification_dir"' EXIT
gh release download "$tag" \
  --pattern NetSpeedMonitor.zip --pattern NetSpeedMonitor.sha256 --dir "$verification_dir"

expected_checksum="$(awk '
  NF == 2 && $2 == "NetSpeedMonitor.zip" && length($1) == 64 && $1 !~ /[^0-9A-Fa-f]/ {
    count++; checksum=tolower($1); next
  }
  { invalid=1 }
  END { if (!invalid && count == 1) print checksum; else exit 1 }
' "$verification_dir/NetSpeedMonitor.sha256")" \
  || { echo "✗ invalid NetSpeedMonitor.sha256 format" >&2; exit 1; }
actual_checksum="$(shasum -a 256 "$verification_dir/NetSpeedMonitor.zip" | awk '{ print $1 }')"
[[ "$actual_checksum" == "$expected_checksum" ]] \
  || { echo "✗ downloaded ZIP checksum does not match NetSpeedMonitor.sha256" >&2; exit 1; }

unzip -q "$verification_dir/NetSpeedMonitor.zip" -d "$verification_dir/extracted"
app="$verification_dir/extracted/NetSpeedMonitor.app"
executable="$app/Contents/MacOS/NetSpeedMonitor"
[[ -f "$executable" ]] \
  || { echo "✗ ZIP does not contain the NetSpeedMonitor executable" >&2; exit 1; }
architectures=" $(lipo -archs "$executable") "
[[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] \
  || { echo "✗ downloaded executable is not universal arm64/x86_64" >&2; exit 1; }
codesign --verify --deep --strict "$app" \
  || { echo "✗ downloaded app has an invalid signature" >&2; exit 1; }

case "$release_state" in
  draft) gh release edit "$tag" --draft=false ;;
  public) echo "▸ $tag is already published" ;;
  *) echo "✗ unexpected release state: ${release_state:-missing}" >&2; exit 1 ;;
esac
"$tap/bump.sh" netspeedmonitor "$version"
echo "✓ released NetSpeedMonitor $tag"
