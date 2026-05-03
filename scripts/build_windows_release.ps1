param(
  [string]$Version = "dev"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = "manual"
}

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$DistRoot = Join-Path $Root "dist"
$ReleaseDir = Join-Path $Root "release"
$InstallerScript = Join-Path $Root "scripts\StreamGlowInstaller.iss"
$IconPath = Join-Path $Root "branding\windows\streamglow.ico"

Set-Location $Root

python scripts/generate_brand_assets.py

if (Test-Path $DistRoot) {
  Remove-Item $DistRoot -Recurse -Force
}

if (Test-Path $ReleaseDir) {
  Remove-Item $ReleaseDir -Recurse -Force
}

pyinstaller `
  --noconfirm `
  --clean `
  --windowed `
  --onedir `
  --name StreamGlow `
  --icon $IconPath `
  --hidden-import tkinter `
  --hidden-import tkinter.messagebox `
  --distpath $DistRoot `
  --workpath (Join-Path $Root "build\pyinstaller") `
  --specpath (Join-Path $Root "build\pyinstaller-spec") `
  --add-data "$Root\overlays;overlays" `
  server.py

Copy-Item LICENSE (Join-Path $DistRoot "StreamGlow\LICENSE.txt")

if (-not (Get-Command iscc -ErrorAction SilentlyContinue)) {
  throw "Inno Setup compiler (iscc) is required but was not found."
}

New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

iscc "/DMyAppVersion=$Version" $InstallerScript | Out-Host

$VersionedInstaller = Join-Path $ReleaseDir "StreamGlow-Setup-$Version.exe"
$LatestInstaller = Join-Path $ReleaseDir "StreamGlow-Setup-latest.exe"

if (-not (Test-Path $VersionedInstaller)) {
  throw "Expected installer missing at $VersionedInstaller"
}

Copy-Item $VersionedInstaller $LatestInstaller -Force
