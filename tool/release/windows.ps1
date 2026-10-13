#requires -Version 7.0
<#
.SYNOPSIS
Build and verify the complete NexaPOS Windows x64 release bundle.
.EXAMPLE
pwsh -File tool/release/windows.ps1 -OutputDirectory C:\releases
.EXAMPLE
pwsh -File tool/release/windows.ps1 -DartDefinesFile config/supabase.local.json -RequireInstaller
.NOTES
Requires Windows x64, Flutter 3.44.0, Visual Studio Desktop development with C++,
Python 3, and (for the installer) Inno Setup 6. Public client configuration only.
No signing identity is invented. Generated EXE and installer remain unsigned.
Native launch/install smoke is separate and uses an ephemeral CI user profile.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [string]$DartDefinesFile = '',
    [string]$IsccPath = '',
    [switch]$RequireInstaller,
    [switch]$RunSmokeTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
    throw 'Windows x64 with the Visual Studio C++ toolchain is required; Linux cannot compile this release.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'build/release/windows-artifacts' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Get-ChildItem -LiteralPath $OutputDirectory -Force) {
    throw 'Choose an empty output directory so an earlier release cannot be mistaken for this build.'
}

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE." }
}

function Assert-PublicConfiguration {
    param([string]$Path)
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($config -isnot [System.Collections.IDictionary]) { throw 'Client configuration must be a JSON object.' }
    $allowed = @('SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY', 'AUTH_REDIRECT_URL', 'OFFLINE_TRUSTED_KEYS_JSON')
    foreach ($entry in $config.GetEnumerator()) {
        if ($entry.Key -notin $allowed -or $entry.Value -isnot [string]) {
            throw 'Client configuration contains an unsupported key or a non-string value.'
        }
    }
    $url = if ($config.Contains('SUPABASE_URL')) { $config['SUPABASE_URL'] } else { '' }
    $key = if ($config.Contains('SUPABASE_PUBLISHABLE_KEY') -and $config['SUPABASE_PUBLISHABLE_KEY']) {
        $config['SUPABASE_PUBLISHABLE_KEY']
    } elseif ($config.Contains('SUPABASE_ANON_KEY')) { $config['SUPABASE_ANON_KEY'] } else { '' }
    if (-not $url -and -not $key) { return $false }
    $uri = $null
    if (-not $url -or -not $key -or -not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not $uri.Host -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Provide an HTTPS project URL and a public client key together.'
    }
    if (-not $key.StartsWith('sb_publishable_')) {
        try {
            $parts = $key.Split('.')
            if ($parts.Count -ne 3) { throw 'Invalid JWT' }
            $payload = $parts[1].Replace('-', '+').Replace('_', '/')
            $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
            $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -AsHashtable
            if ($claims['role'] -ne 'anon') { throw 'Privileged key' }
        } catch { throw 'Only a Supabase publishable key or legacy anon JWT may be embedded.' }
    }
    # The fallback key is also embedded in Dart defines: validate it even when unused.
    if ($config.Contains('SUPABASE_ANON_KEY') -and $config['SUPABASE_ANON_KEY'] -and $key -ne $config['SUPABASE_ANON_KEY']) {
        throw 'Use one public client key field; omit the unused fallback key.'
    }
    return $true
}

function Assert-X64Pe {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw "Invalid PE file: $Path" }
    $offset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($offset -lt 64 -or $offset + 6 -gt $bytes.Length -or
        [BitConverter]::ToUInt32($bytes, $offset) -ne 0x00004550 -or
        [BitConverter]::ToUInt16($bytes, $offset + 4) -ne 0x8664) {
        throw "Expected a Windows x64 PE file: $Path"
    }
}

$originalLocation = Get-Location
try {
    Set-Location $repo
    $flutter = (& flutter --version --machine | Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $flutter.frameworkVersion -ne '3.44.0') { throw 'Use the exact validated Flutter version: 3.44.0.' }
    Invoke-Checked flutter @('doctor', '-v')
    Invoke-Checked flutter @('config', '--enable-windows-desktop')
    Invoke-Checked python @('tool/verify_receipt_fonts.py')
    Invoke-Checked flutter @('pub', 'get', '--enforce-lockfile')
    $lockBefore = (Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash
    Invoke-Checked dart @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
    Invoke-Checked flutter @('analyze', '--no-pub')
    Invoke-Checked flutter @('test', '--no-pub', '--concurrency=4')
    # Flutter 3.44 regenerates release plugin files only when pub is enabled.
    $buildArgs = @('build', 'windows', '--release')
    $configured = $false
    if ($DartDefinesFile) {
        $DartDefinesFile = (Resolve-Path -LiteralPath $DartDefinesFile).Path
        $configured = Assert-PublicConfiguration $DartDefinesFile
        $buildArgs += "--dart-define-from-file=$DartDefinesFile"
    }
    Invoke-Checked flutter $buildArgs
    if ((Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash -ne $lockBefore) {
        throw 'Dependency lockfile changed during the build. Review it before distributing this release.'
    }

    $releaseDirectory = Join-Path $repo 'build/windows/x64/runner/Release'
    $required = @('NexaPOS.exe', 'flutter_windows.dll', 'app_links_plugin.dll',
        'flutter_secure_storage_windows_plugin.dll', 'printing_plugin.dll', 'pdfium.dll',
        'url_launcher_windows_plugin.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets')
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory $relative))) { throw "Missing release runtime file: $relative" }
    }
    Assert-X64Pe (Join-Path $releaseDirectory 'NexaPOS.exe')
    $cipherFiles = @(Get-ChildItem -LiteralPath $releaseDirectory -Recurse -File | Where-Object { $_.Name -match '^sqlcipher.*\.dll$' })
    if ($cipherFiles.Count -ne 1) { throw 'Exactly one bundled SQLCipher native DLL is required.' }
    Assert-X64Pe $cipherFiles[0].FullName
    $expectedCipherHash = '1a4b81f2027adf809bcb9a8a2cecae3506ec62ebc9a5391d2fd5f4bfbdda4f0c'
    if ((Get-FileHash -LiteralPath $cipherFiles[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedCipherHash) {
        throw 'The bundled SQLCipher DLL differs from sqlite3 3.5.2 Windows x64 native-asset provenance.'
    }
    $fonts = Get-Content -LiteralPath 'assets/fonts/PROVENANCE.json' -Raw | ConvertFrom-Json -AsHashtable
    foreach ($font in $fonts['packaged_fonts'].GetEnumerator()) {
        $fontPath = Join-Path $releaseDirectory "data/flutter_assets/assets/fonts/$($font.Key)"
        if ((Get-FileHash -LiteralPath $fontPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $font.Value) {
            throw 'A packaged receipt font differs from its licensed source asset.'
        }
    }

    # App-local redistributables make the ZIP usable without a separate VC++ setup.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio vswhere.exe is required to locate licensed redistributable DLLs.' }
    $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vsPath) { throw 'Visual Studio C++ runtime redistributables were not found.' }
    $crt = Get-ChildItem -Path (Join-Path $vsPath 'VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT') -Directory |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $crt) { throw 'Install the Visual Studio x64 MSVC redistributable component before packaging.' }
    $stage = Join-Path $OutputDirectory 'NexaPOS'
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -Path (Join-Path $releaseDirectory '*') -Destination $stage -Recurse
    Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $stage
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        Assert-X64Pe (Join-Path $stage $dll)
    }
    # Include the redistributable license from the installed toolchain, when supplied.
    $redistLicense = Get-ChildItem -Path (Join-Path $vsPath 'VC/Redist/MSVC/*/onecore/License.txt'),
        (Join-Path $vsPath 'VC/Redist/MSVC/*/License.txt') -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($redistLicense) { Copy-Item -LiteralPath $redistLicense.FullName -Destination (Join-Path $stage 'MSVC-Redistributable-License.txt') }

    $manifest = @(Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/'); bytes = $_.Length;
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'NexaPOS-Windows-Manifest.json') -Encoding utf8
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $OutputDirectory 'NexaPOS-Windows-Portable.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    $roundtrip = Join-Path $OutputDirectory 'zip-verification'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $roundtrip)
    $roundtripFiles = @(Get-ChildItem -LiteralPath $roundtrip -File -Recurse)
    if ($roundtripFiles.Count -ne $manifest.Count) { throw 'Portable ZIP does not contain the complete runtime file set.' }
    foreach ($item in $manifest) {
        $expanded = Join-Path $roundtrip $item.path
        if ((Get-Item -LiteralPath $expanded).Length -ne $item.bytes -or
            (Get-FileHash -LiteralPath $expanded -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) {
            throw "Portable ZIP round-trip verification failed: $($item.path)"
        }
    }

    if (-not $IsccPath) {
        $candidate = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
        if (Test-Path -LiteralPath $candidate) { $IsccPath = $candidate }
    }
    $installerStatus = 'unavailable: Inno Setup 6 is not installed'
    if ($IsccPath) {
        $versionLine = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
        if (-not $versionLine) { throw 'Application version could not be read from pubspec.yaml.' }
        $version = $versionLine.Matches[0].Groups[1].Value
        Invoke-Checked $IsccPath @("/DSourceDir=$stage", "/DOutputDir=$OutputDirectory", "/DAppVersion=$version",
            "/DAppIcon=$repo/windows/runner/resources/app_icon.ico", (Join-Path $PSScriptRoot 'windows-installer.iss'))
        $installer = Join-Path $OutputDirectory 'NexaPOS-Windows-Setup.exe'
        if (-not (Test-Path -LiteralPath $installer) -or (Get-Item -LiteralPath $installer).Length -eq 0) { throw 'Installer compiler did not produce a nonempty installer.' }
        $installerStatus = 'generated; unsigned'
    } elseif ($RequireInstaller) { throw 'Inno Setup 6 is required for the requested installer.' }

    $smokeStatus = 'not run; native launch and installer validation remain outstanding'
    if ($RunSmokeTests) {
        & (Join-Path $PSScriptRoot 'windows-smoke.ps1') -PortableDirectory $roundtrip -ArtifactDirectory $OutputDirectory
        $smokeStatus = 'passed: extracted portable launch; installed launch and uninstall when installer exists'
    }
    $artifacts = @(Get-ChildItem -LiteralPath $OutputDirectory -File | Where-Object { $_.Extension -in @('.zip', '.exe', '.json') })
    $artifacts | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
    } | Set-Content -LiteralPath (Join-Path $OutputDirectory 'NexaPOS-Windows-SHA256SUMS.txt') -Encoding utf8
    @"
NexaPOS Windows Build Report
Build status: PASS (flutter build windows --release completed)
Flutter: $($flutter.frameworkVersion)
Dart: $($flutter.dartSdkVersion)
Architecture: Windows x64
EXE: NexaPOS.exe
Portable ZIP: NexaPOS-Windows-Portable.zip
ZIP bytes: $((Get-Item -LiteralPath $zip).Length)
ZIP integrity: all $($manifest.Count) runtime files matched after extraction
SQLCipher: sqlite3 3.5.2 pinned Windows x64 DLL SHA256 verified
Receipt fonts: packaged bytes match licensed source assets
MSVC runtime: app-local x64 redistributable DLLs included
Installer: $installerStatus
Startup/installer smoke: $smokeStatus
flutter analyze: PASS
Flutter tests: PASS
Function tests: not executed by this Windows script
Database/SQL tests: not executed by this Windows script
Public Supabase client configuration supplied: $configured
Known limitations: unsigned Windows EXE/installer; SmartScreen may prompt. No live
Supabase/Auth/email or physical printer/scanner checks are implied by these checks.
An unconfigured build opens the existing Not Yet Connected workspace. A configured
build still requires the real schema, Auth callbacks, Edge functions and delivery.
"@ | Set-Content -LiteralPath (Join-Path $OutputDirectory 'NexaPOS-Windows-Build-Report.txt') -Encoding utf8
    Write-Host "Verified Windows release artifacts: $OutputDirectory"
} finally { Set-Location $originalLocation }
