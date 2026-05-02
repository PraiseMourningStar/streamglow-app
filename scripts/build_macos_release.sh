#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${GITHUB_REF_NAME:-dev}}"
DERIVED_DATA="$ROOT/build/ReleaseDerivedData"
APP_BUILD_DIR="$DERIVED_DATA/Build/Products/Release"
APP_PATH="$APP_BUILD_DIR/StreamGlow.app"
RELEASE_DIR="$ROOT/release"
DMG_STAGE_DIR="$ROOT/build/dmg-stage"
DMG_PATH="$RELEASE_DIR/StreamGlow-${VERSION}.dmg"
ENTITLEMENTS="$ROOT/StreamGlow-DirectDist.entitlements"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"

cd "$ROOT"

normalize_project_format() {
  local project_file="$ROOT/StreamGlow.xcodeproj/project.pbxproj"
  if [[ -f "$project_file" ]]; then
    perl -0pi -e 's/objectVersion = 77;/objectVersion = 60;/g; s/preferredProjectObjectVersion = 77;/preferredProjectObjectVersion = 60;/g' "$project_file"
  fi
}

python3 scripts/generate_brand_assets.py
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi
normalize_project_format

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    echo "Signing identity '$SIGNING_IDENTITY' was requested, but it is not installed in the keychain." >&2
    echo "Import a Developer ID Application .p12 certificate, or leave APPLE_SIGNING_IDENTITY unset for an unsigned local DMG." >&2
    exit 1
  fi

  xcodebuild \
    -project StreamGlow.xcodeproj \
    -scheme StreamGlow \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    ENABLE_HARDENED_RUNTIME=YES \
    clean build
else
  xcodebuild \
    -project StreamGlow.xcodeproj \
    -scheme StreamGlow \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    clean build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle missing at $APP_PATH" >&2
  exit 1
fi

rm -rf "$RELEASE_DIR" "$DMG_STAGE_DIR"
mkdir -p "$RELEASE_DIR" "$DMG_STAGE_DIR"

cp -R "$APP_PATH" "$DMG_STAGE_DIR/StreamGlow.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"
find "$DMG_STAGE_DIR" -name '.DS_Store' -delete
xattr -cr "$DMG_STAGE_DIR/StreamGlow.app" 2>/dev/null || true

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" "$DMG_STAGE_DIR/StreamGlow.app"
fi

hdiutil create \
  -volname "StreamGlow" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Notarization requires a signed app. Import a Developer ID Application certificate before submitting." >&2
    exit 1
  fi

  xcrun notarytool submit "$DMG_PATH" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait
  xcrun stapler staple "$DMG_PATH"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Notarization requires a signed app. Import a Developer ID Application certificate before submitting." >&2
    exit 1
  fi

  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$DMG_PATH"
fi

cp "$DMG_PATH" "$RELEASE_DIR/StreamGlow-latest.dmg"

echo "Created $DMG_PATH"
echo "Created $RELEASE_DIR/StreamGlow-latest.dmg"
