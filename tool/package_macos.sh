#!/bin/bash
# Build a distributable preview; Developer ID signing/notarization is separate.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter clean
bash tool/prepare_sources.sh
release_name="$(dart run tool/generate_app_version.dart --release)"
build_name="$(dart run tool/generate_app_version.dart --build-name)"
build_number="$(dart run tool/generate_app_version.dart --build-number)"
if [[ -n "${1:-}" && "$1" != "$release_name" ]]; then
  echo 'Release name must match pubspec.yaml' >&2
  exit 1
fi
if [[ -n "${INKJIAN_NOTARY_PROFILE:-}" && -z "${INKJIAN_SIGN_IDENTITY:-}" ]]; then
  echo 'Notarization requires INKJIAN_SIGN_IDENTITY' >&2
  exit 1
fi
if [[ ! "$release_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo 'Invalid release name' >&2
  exit 1
fi
build_options=(--release --build-name "$build_name" --build-number "$build_number")
if [[ -n "${INKJIAN_GITHUB_CLIENT_ID:-}" || -n "${INKJIAN_GITHUB_APP_SLUG:-}" ]]; then
  if [[ -z "${INKJIAN_GITHUB_CLIENT_ID:-}" || -z "${INKJIAN_GITHUB_APP_SLUG:-}" ]]; then
    echo 'Set both INKJIAN_GITHUB_CLIENT_ID and INKJIAN_GITHUB_APP_SLUG' >&2
    exit 1
  fi
  build_options+=("--dart-define=INKJIAN_GITHUB_CLIENT_ID=$INKJIAN_GITHUB_CLIENT_ID")
  build_options+=("--dart-define=INKJIAN_GITHUB_APP_SLUG=$INKJIAN_GITHUB_APP_SLUG")
fi
flutter build macos "${build_options[@]}"
app_path="build/macos/Build/Products/Release/InkJian.app"
if [[ -d "$app_path/Contents/Frameworks/App.framework/Resources/flutter_assets/template" ]]; then
  echo 'Templates must not be bundled in the application' >&2
  exit 1
fi
if [[ -n "${INKJIAN_SIGN_IDENTITY:-}" ]]; then
  while IFS= read -r -d '' binary; do
    if file -b "$binary" | grep -q 'Mach-O'; then
      codesign --force --options runtime --timestamp --sign "$INKJIAN_SIGN_IDENTITY" "$binary"
    fi
  done < <(find "$app_path" -type f -print0)
  codesign --force --options runtime --timestamp --sign "$INKJIAN_SIGN_IDENTITY" \
    --entitlements macos/Runner/Release.entitlements "$app_path"
fi
codesign --verify --deep --strict "$app_path"
app_archs="$(lipo -archs "$app_path/Contents/MacOS/InkJian")"
if [[ "$app_archs" == *arm64* && "$app_archs" == *x86_64* ]]; then
  architecture=universal
elif [[ "$app_archs" == *arm64* ]]; then
  architecture=arm64
else
  architecture=x86_64
fi
output_dir="build/releases/$release_name"
mkdir -p "$output_dir"
base="InkJian-$release_name-macos-$architecture"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/inkjian-package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_path" "$staging_dir/InkJian.app"
if [[ -n "${INKJIAN_NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$staging_dir/InkJian.app" "$staging_dir/notarize.zip"
  xcrun notarytool submit "$staging_dir/notarize.zip" --keychain-profile "$INKJIAN_NOTARY_PROFILE" --wait
  xcrun stapler staple "$staging_dir/InkJian.app"
  rm "$staging_dir/notarize.zip"
fi
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname 'InkJian' -srcfolder "$staging_dir" -ov -format UDZO "$output_dir/$base.dmg"
if [[ -n "${INKJIAN_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$INKJIAN_SIGN_IDENTITY" "$output_dir/$base.dmg"
fi
if [[ -n "${INKJIAN_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$output_dir/$base.dmg" --keychain-profile "$INKJIAN_NOTARY_PROFILE" --wait
  xcrun stapler staple "$output_dir/$base.dmg"
  xcrun stapler validate "$output_dir/$base.dmg"
fi
hdiutil verify "$output_dir/$base.dmg"
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/InkJian.app" "$output_dir/$base.zip"
(
  cd "$output_dir"
  shasum -a 256 "$base.dmg" "$base.zip" > SHA256SUMS.txt
)
echo "Packaged: $output_dir ($app_archs)"
