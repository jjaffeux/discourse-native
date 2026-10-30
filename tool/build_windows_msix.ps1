[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+\.0$')]
    [string]$StoreVersion
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'MSIX builds require Windows and Visual Studio C++ tools.' }
$parts = @($StoreVersion.Split('.') | ForEach-Object { [int]$_ })
if ($parts[0] -lt 1 -or @($parts | Where-Object { $_ -gt 65535 }).Count -gt 0) {
    throw 'The Store version must be a.b.c.0, with a positive major version and components at most 65535.'
}
$project = Split-Path -Parent $PSScriptRoot
Push-Location $project
try {
    flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    $buildName = "$($parts[0]).$($parts[1]).$($parts[2])"
    flutter build windows --release --build-name $buildName --build-number 0 `
        --dart-define="DISCOURSE_NATIVE_VERSION=$buildName"
    if ($LASTEXITCODE -ne 0) { throw 'The Windows build failed.' }
    dart run msix:create --version $StoreVersion --output-path build/windows/msix `
        --output-name "DiscourseNative-$StoreVersion-x64"
    if ($LASTEXITCODE -ne 0) { throw 'MSIX packaging failed.' }
    $package = "build/windows/msix/DiscourseNative-$StoreVersion-x64.msix"
    if (-not (Test-Path $package)) { throw "MSIX output missing: $package" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $package))
    try {
        $reader = [System.IO.StreamReader]::new($archive.GetEntry('AppxManifest.xml').Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($manifest.Package.Identity.Name -ne 'Discourse.DiscourseNative' -or
            $manifest.Package.Identity.Publisher -ne 'CN=4A2D3327-D000-4EEA-AE19-9F753B328EF2' -or
            $manifest.Package.Identity.Version -ne $StoreVersion -or
            $manifest.Package.Identity.ProcessorArchitecture -ne 'x64') {
            throw 'The generated manifest does not match the Store package identity.'
        }
        foreach ($required in @('discourse_native.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
            if ($archive.Entries.FullName -notcontains $required) {
                throw "The MSIX is missing $required."
            }
        }
    } finally { $archive.Dispose() }
    Get-FileHash -Algorithm SHA256 $package
} finally {
    Pop-Location
}
