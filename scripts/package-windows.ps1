# Ensure we are in the project root
$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
Set-Location $ProjectRoot

$BundleDir = "build\windows\x64\runner\Release"
$OutputName = "jof-launcher-windows.zip"

if (-not (Test-Path $BundleDir)) {
    Write-Error "Error: Bundle directory not found at $BundleDir"
    Write-Host "Please run 'flutter build windows --release' first."
    exit 1
}

Write-Host "Creating $OutputName from $BundleDir..."

# Create a temporary directory for the archive structure
$TempDir = "build\windows\x64\release\jof-launcher"
if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
}
New-Item -ItemType Directory -Path $TempDir

# Copy bundle contents to the temporary directory
Copy-Item -Recurse -Path "$BundleDir\*" -Destination $TempDir

# Copy required Visual C++ Runtime DLLs
# These DLLs are typically located in the Windows System32 directory
$SystemDlls = @(
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll"
)

foreach ($dll in $SystemDlls) {
    $dllPath = Join-Path $env:SystemRoot "System32\$dll"
    if (Test-Path $dllPath) {
        Copy-Item $dllPath -Destination $TempDir
        Write-Host "Copied $dll to package"
    } else {
        Write-Warning "Warning: $dll not found at $dllPath"
    }
}

# Create the zip archive with the jof-launcher directory as the top level
if (Test-Path $OutputName) {
    Remove-Item $OutputName
}
Compress-Archive -Path $TempDir -DestinationPath $OutputName

# Cleanup
Remove-Item -Recurse -Force $TempDir

Write-Host "Done! $OutputName created in the project root."
