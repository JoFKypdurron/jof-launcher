# Packages a `flutter build windows --release` bundle as:
#   jof-launcher-windows-setup.exe  per-user installer (needs Inno Setup 6)
#   jof-launcher-windows.zip        portable copy
#
# Usage: .\scripts\package-windows.ps1 [-Version 1.2.3] [-RequireInstaller]
# The version defaults to the one in pubspec.yaml. Without -RequireInstaller a
# missing Inno Setup only skips the installer, so the zip can still be built
# locally.
param(
    [string]$Version,
    [switch]$RequireInstaller
)

$ErrorActionPreference = "Stop"

# Ensure we are in the project root
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
Set-Location $ProjectRoot

$BundleDir = "build\windows\x64\runner\Release"
$StageDir = "build\windows\package\jof-launcher"
$ZipName = "jof-launcher-windows.zip"
$InstallerName = "jof-launcher-windows-setup.exe"

if (-not (Test-Path "$BundleDir\jof-launcher.exe")) {
    Write-Error "jof-launcher.exe not found in $BundleDir. Run 'flutter build windows --release' first."
    exit 1
}

if (-not $Version) {
    $line = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    $Version = $line.Matches[0].Groups[1].Value -replace '\+.*$', ''
}
Write-Host "Packaging JoF Launcher $Version"

# Stage the bundle plus the Visual C++ runtime, so the launcher starts on a
# machine that never installed the redistributable.
if (Test-Path $StageDir) {
    Remove-Item -Recurse -Force $StageDir
}
New-Item -ItemType Directory -Path $StageDir | Out-Null
Copy-Item -Recurse -Path "$BundleDir\*" -Destination $StageDir

$SystemDlls = @(
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll"
)

foreach ($dll in $SystemDlls) {
    $dllPath = Join-Path $env:SystemRoot "System32\$dll"
    if (Test-Path $dllPath) {
        Copy-Item $dllPath -Destination $StageDir
        Write-Host "Copied $dll to package"
    } else {
        Write-Warning "$dll not found at $dllPath"
    }
}

# Portable zip, with the jof-launcher directory as the top level.
if (Test-Path $ZipName) {
    Remove-Item $ZipName
}
Compress-Archive -Path $StageDir -DestinationPath $ZipName
Write-Host "Created $ZipName"

# Installer.
$Iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $Iscc) {
    $Iscc = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $Iscc) {
    if ($RequireInstaller) {
        Write-Error "Inno Setup 6 (ISCC.exe) not found."
        exit 1
    }
    Write-Warning "Inno Setup 6 not found; skipping $InstallerName."
    exit 0
}

if (Test-Path $InstallerName) {
    Remove-Item $InstallerName
}
& $Iscc `
    "/DAppVersion=$Version" `
    "/DSourceDir=$(Resolve-Path $StageDir)" `
    "/DOutputDir=$ProjectRoot" `
    "windows\installer\jof-launcher.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
Write-Host "Created $InstallerName"
