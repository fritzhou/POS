#requires -Version 7.0
<# Native first-frame/process smoke on an ephemeral GitHub Windows runner only.
It does not log in, create business data, send email or claim live backend tests. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortableDirectory,
    [Parameter(Mandatory)][string]$ArtifactDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or $env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
    throw 'Run native smoke checks on an ephemeral GitHub Windows runner; this avoids using an existing user profile or vault.'
}
function Test-NativeLaunch {
    param([string]$Directory, [string]$Label)
    $exe = Join-Path $Directory 'NexaPOS.exe'
    $process = Start-Process -FilePath $exe -WorkingDirectory $Directory -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        do {
            Start-Sleep -Milliseconds 250
            $process.Refresh()
            if ($process.HasExited) { throw "$Label exited before its first Flutter window, code $($process.ExitCode)." }
            $shown = $process.MainWindowHandle -ne [IntPtr]::Zero -and $process.MainWindowTitle -eq 'NexaPOS'
        } until ($shown -or [DateTime]::UtcNow -ge $deadline)
        if (-not $shown) { throw "$Label did not display a NexaPOS window after the first Flutter frame." }
        Start-Sleep -Seconds 12
        $process.Refresh()
        if ($process.HasExited) { throw "$Label exited during startup smoke, code $($process.ExitCode)." }
        "${Label}: PASS; first-frame window observed and process remained alive for 12 seconds" |
            Add-Content -LiteralPath (Join-Path $ArtifactDirectory 'NexaPOS-Windows-Smoke.txt') -Encoding utf8
    } finally {
        $process.Refresh()
        if (-not $process.HasExited) {
            $process.CloseMainWindow() | Out-Null
            if (-not $process.WaitForExit(5000)) { $process.Kill(); $process.WaitForExit() }
        }
        $process.Dispose()
    }
}

Test-NativeLaunch $PortableDirectory 'Extracted portable release'
$installer = Join-Path $ArtifactDirectory 'NexaPOS-Windows-Setup.exe'
if (Test-Path -LiteralPath $installer) {
    $installPath = Join-Path $env:RUNNER_TEMP ('nexapos-installer-smoke-' + [Guid]::NewGuid().ToString('N'))
    $logPath = Join-Path $ArtifactDirectory 'NexaPOS-Windows-Installer-Smoke.log'
    $process = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
        ('/DIR="{0}"' -f $installPath), ('/LOG="{0}"' -f $logPath)) -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Installer smoke failed, code $($process.ExitCode)." }
    $uninstaller = Join-Path $installPath 'unins000.exe'
    if (-not (Test-Path -LiteralPath $uninstaller)) { throw 'Installer did not include an uninstaller.' }
    Test-NativeLaunch $installPath 'Installed release'
    $process = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru -Wait
    if ($process.ExitCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $installPath 'NexaPOS.exe'))) {
        throw 'Installer smoke could not uninstall its task-owned application files.'
    }
    'Installer: PASS; silent install, installed launch, uninstaller and removal verified' |
        Add-Content -LiteralPath (Join-Path $ArtifactDirectory 'NexaPOS-Windows-Smoke.txt') -Encoding utf8
}
