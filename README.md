# StreamGlow

Native now-playing app for OBS on macOS, with a packaged Windows fallback release.

## Download

[Download for macOS](https://github.com/PraiseMourningStar/streamglow-app/releases/latest/download/StreamGlow-latest.dmg)

[Download for Windows](https://github.com/PraiseMourningStar/streamglow-app/releases/latest/download/StreamGlow-Setup-latest.exe)

If you just want the latest build page, use [GitHub Releases](https://github.com/PraiseMourningStar/streamglow-app/releases/latest).

## What ships

- macOS: a SwiftUI desktop app with a live preview, OBS URL tools, theme controls, and bundled overlay server
- Windows: a packaged `.exe` installer for the legacy Python overlay server
- GitHub Releases: automated DMG and Windows installer builds on tagged releases, plus stable `latest` download links

## macOS flow

1. Download the DMG from the macOS link above.
2. Drag `StreamGlow.app` into Applications.
3. Launch the app.
4. If Apple blocks it the first time, go to `System Settings > Privacy & Security`, click `Open Anyway`, then launch it again. You can also right-click the app and choose `Open`.
5. When macOS asks, allow StreamGlow to control Music and Spotify.
6. Copy the local OBS URL and paste it into an OBS Browser Source.

The native app serves the overlay on `http://127.0.0.1:8974/`.

## Windows flow

1. Download the Windows installer from the Windows link above.
2. Run the `.exe` installer.
3. Launch StreamGlow from the desktop or Start menu shortcut.
4. Add `http://127.0.0.1:8974/` as an OBS Browser Source.

## Release flow

Push a version tag and GitHub Actions will build both installers and attach them to a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Published assets include both versioned files and stable latest aliases:

- `StreamGlow-<version>.dmg`
- `StreamGlow-latest.dmg`
- `StreamGlow-Setup-<version>.exe`
- `StreamGlow-Setup-latest.exe`

## Local development

### macOS app

```bash
python3 scripts/generate_brand_assets.py
xcodegen generate
xcodebuild -project StreamGlow.xcodeproj -scheme StreamGlow -configuration Debug -derivedDataPath build/DerivedData build
```

### Legacy Windows server

```bash
python3 -m py_compile server.py
```

## Optional notarization

If you add Apple signing and notarization secrets in GitHub Actions, the macOS DMG can be signed and notarized automatically. Without those secrets, the workflow still builds a DMG, but macOS will usually show the first-run unblock flow described above.

Signing and notarization use different Apple credentials:

- `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_KEYCHAIN_PASSWORD`: a Developer ID Application certificate exported as `.p12`. This signs the app.
- `APPLE_SIGNING_IDENTITY`: optional. If omitted, the release script uses the first installed `Developer ID Application` identity.
- `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER_ID`: App Store Connect API key credentials for notarization.
- `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`: older Apple ID notarization credentials. Use these instead of the API key secrets, not in addition to them.

An App Store Connect `.p8` key cannot sign the app by itself; it only authenticates the notarization request after the app has been signed with a Developer ID Application certificate.

## License

Free to use, share, and modify.
