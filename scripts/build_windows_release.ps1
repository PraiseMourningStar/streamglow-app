param(
  [string]$Version = "dev"
)

$ErrorActionPreference = "Stop"

function Get-PeSubsystem {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 0x100 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
    throw "Not a valid Windows executable: $Path"
  }

  $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
  if ($peOffset -lt 0 -or $peOffset + 0x5c -ge $bytes.Length) {
    throw "Invalid PE header offset in $Path"
  }

  $signature = [System.Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4)
  if ($signature -ne "PE`0`0") {
    throw "Missing PE signature in $Path"
  }

  $optionalHeaderOffset = $peOffset + 24
  return [BitConverter]::ToUInt16($bytes, $optionalHeaderOffset + 0x44)
}

function Assert-WindowsGuiSubsystem {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $subsystem = Get-PeSubsystem -Path $Path
  if ($subsystem -ne 2) {
    throw "Expected a Windows GUI executable, but $Path has PE subsystem $subsystem. Refusing to package a console app."
  }

  Write-Host "Verified Windows GUI subsystem for $Path"
}

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
  --noconsole `
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

$AppExe = Join-Path $DistRoot "StreamGlow\StreamGlow.exe"
Assert-WindowsGuiSubsystem -Path $AppExe

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

Assert-WindowsGuiSubsystem -Path $VersionedInstaller
Copy-Item $VersionedInstaller $LatestInstaller -Force
