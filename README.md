# StreamGlow

Native macOS now-playing overlays for OBS. StreamGlow reads Music and Spotify, serves a local browser-source overlay, and gives you a live preview before you paste anything into your scene.

![StreamGlow app preview](docs/streamglow-preview.png)

## Download

[Download StreamGlow for macOS](https://github.com/PraiseMourningStar/streamglow-app/releases/latest/download/StreamGlow-latest.dmg)

The full release page is here: [GitHub Releases](https://github.com/PraiseMourningStar/streamglow-app/releases/latest).

## What It Does

- Serves your OBS overlay at `http://127.0.0.1:8974/`
- Reads now-playing metadata from Music and Spotify
- Shows a live in-app preview of the overlay
- Copies the OBS browser-source URL in one click
- Lets you tune colors, glow, transparency, text size, tile size, and compactness
- Packages as a signed/notarized macOS DMG when Apple release secrets are configured

## Setup

1. Download the latest DMG.
2. Drag `StreamGlow.app` into Applications.
3. Launch StreamGlow.
4. If macOS blocks first launch, go to `System Settings > Privacy & Security`, click `Open Anyway`, then launch again.
5. Allow StreamGlow to control Music and Spotify when macOS asks.
6. Copy `http://127.0.0.1:8974/` into an OBS Browser Source.

Recommended OBS browser-source size: `720 x 220` to start.

## Platform Support

StreamGlow is currently macOS-first. The old Windows installer path has been retired because it was not reliable enough to keep shipping. Future releases publish the macOS DMG only.

## Local Development

```bash
python3 scripts/generate_brand_assets.py
xcodegen generate
xcodebuild -project StreamGlow.xcodeproj -scheme StreamGlow -configuration Debug -derivedDataPath build/DerivedData build
```

## Release Flow

Push a version tag and GitHub Actions will build and publish the macOS DMG:

```bash
git tag v1.0.7
git push origin v1.0.7
```

Published assets:

- `StreamGlow-<version>.dmg`
- `StreamGlow-latest.dmg`

## Signing And Notarization

The release workflow can sign and notarize automatically when these GitHub Actions secrets are set:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_SIGNING_IDENTITY` optional
- `APPLE_API_KEY_P8_BASE64`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

Without Apple signing secrets, the workflow still builds a DMG, but macOS will show the normal first-run security prompt.

## License

Free to use, share, and modify.
