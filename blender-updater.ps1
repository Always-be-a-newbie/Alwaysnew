<#
.SYNOPSIS
    Check and install the latest official Blender stable release on Windows.

.DESCRIPTION
    Queries download.blender.org for the newest stable Windows MSI, compares it
    with the locally installed version, and can silently install updates.
    Also registers a weekly Task Scheduler job for unattended updates.

.EXAMPLE
    .\blender-updater.ps1 check
.EXAMPLE
    .\blender-updater.ps1 update
.EXAMPLE
    .\blender-updater.ps1 schedule -DayOfWeek Sunday -At 10:00
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('check', 'update', 'schedule', 'unschedule', 'status')]
    [string]$Command = 'status',

    [switch]$Force,

    [ValidateSet('Stable')]
    [string]$Channel = 'Stable',

    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string]$DayOfWeek = 'Sunday',

    [string]$At = '10:00',

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'lib\Get-LatestRelease.ps1')
. (Join-Path $scriptRoot 'lib\Get-InstalledBlender.ps1')
. (Join-Path $scriptRoot 'lib\Install-Blender.ps1')
. (Join-Path $scriptRoot 'lib\Register-UpdateTask.ps1')

function Import-UpdaterConfig {
    param(
        [string]$Path
    )

    $defaults = @{
        InstallPath   = $null
        ReleaseRootUrl = 'https://download.blender.org/release/'
        DataRoot      = '%LOCALAPPDATA%\Alwaysnew\BlenderUpdater'
        CacheDir      = '%LOCALAPPDATA%\Alwaysnew\BlenderUpdater\cache'
        LogDir        = '%LOCALAPPDATA%\Alwaysnew\BlenderUpdater\logs'
        Channel       = 'Stable'
    }

    $candidate = $null
    if ($Path) {
        $candidate = $Path
    }
    else {
        $defaultPath = Join-Path $scriptRoot 'config.json'
        if (Test-Path -LiteralPath $defaultPath) {
            $candidate = $defaultPath
        }
    }

    if ($candidate) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Config file not found: $candidate"
        }

        $raw = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            $defaults[$prop.Name] = $prop.Value
        }
    }

    return $defaults
}

function Show-VersionComparison {
    param(
        $Installed,
        $Release
    )

    $localText = if ($Installed.VersionText) { $Installed.VersionText } else { '(not installed)' }
    Write-Host "Local Blender : $localText"
    if ($Installed.ExePath) {
        Write-Host "Local path    : $($Installed.ExePath)"
    }
    if ($Installed.Source) {
        Write-Host "Detected via  : $($Installed.Source)"
    }
    Write-Host "Remote Blender: $($Release.VersionText) ($($Release.Architecture))"
    Write-Host "Download URL  : $($Release.DownloadUrl)"

    if ($Installed.IsSteam) {
        Write-Host ""
        Write-Host "Warning: Steam install detected. This tool updates the official MSI from blender.org and will not manage Steam builds." -ForegroundColor Yellow
    }
}

function Test-UpdateNeeded {
    param(
        $Installed,
        $Release,
        [switch]$Force
    )

    if ($Force) {
        return $true
    }
    if ($null -eq $Installed.Version) {
        return $true
    }
    return ($Release.Version -gt $Installed.Version)
}

$config = Import-UpdaterConfig -Path $ConfigPath
if ($Channel) {
    $config.Channel = $Channel
}

$paths = $null
$paths = Get-UpdaterPaths -Config $config
$whatIf = [bool]$WhatIfPreference

try {
    switch ($Command) {
        'check' {
            $release = Get-LatestBlenderRelease -ReleaseRootUrl $config.ReleaseRootUrl
            $installed = Get-InstalledBlender -ConfiguredInstallPath $config.InstallPath
            Show-VersionComparison -Installed $installed -Release $release

            if (Test-UpdateNeeded -Installed $installed -Release $release -Force:$Force) {
                Write-Host ""
                Write-Host "Update available: $($release.VersionText)" -ForegroundColor Green
                exit 2
            }

            Write-Host ""
            Write-Host "Already up to date." -ForegroundColor Green
            exit 0
        }

        'update' {
            $release = Get-LatestBlenderRelease -ReleaseRootUrl $config.ReleaseRootUrl
            $installed = Get-InstalledBlender -ConfiguredInstallPath $config.InstallPath
            Show-VersionComparison -Installed $installed -Release $release
            Write-UpdaterLog -LogDir $paths.Logs -Message "Command=update channel=$($config.Channel) force=$Force"

            if (-not (Test-UpdateNeeded -Installed $installed -Release $release -Force:$Force)) {
                Write-UpdaterLog -LogDir $paths.Logs -Message "Already up to date ($($release.VersionText))"
                Write-Host ""
                Write-Host "Already up to date." -ForegroundColor Green
                exit 0
            }

            if ($whatIf -or $PSCmdlet.ShouldProcess($release.DownloadUrl, "Download and install Blender $($release.VersionText)")) {
                $result = Install-BlenderRelease -Release $release -Config $config -WhatIf:$whatIf -Force:$Force
                if ($result.Success) {
                    Write-Host ""
                    if ($result.WhatIf) {
                        Write-Host "WhatIf complete for Blender $($result.Version)."
                    }
                    else {
                        Write-Host "Blender $($result.Version) installed successfully." -ForegroundColor Green
                    }
                    exit 0
                }
            }
            exit 1
        }

        'schedule' {
            $task = Register-BlenderUpdateTask -UpdaterScriptPath $PSCommandPath -DayOfWeek $DayOfWeek -At $At -WhatIf:$whatIf
            if ($whatIf) {
                exit 0
            }
            Write-Host "Scheduled task '$($task.TaskName)' registered: $DayOfWeek at $At" -ForegroundColor Green
            Write-Host "It will run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" update"
            exit 0
        }

        'unschedule' {
            Unregister-BlenderUpdateTask -WhatIf:$whatIf | Out-Null
            exit 0
        }

        'status' {
            $release = Get-LatestBlenderRelease -ReleaseRootUrl $config.ReleaseRootUrl
            $installed = Get-InstalledBlender -ConfiguredInstallPath $config.InstallPath
            $taskStatus = Get-BlenderUpdaterTaskStatus

            Show-VersionComparison -Installed $installed -Release $release
            Write-Host ""
            Write-Host "Scheduled task: $($taskStatus.TaskName)"
            Write-Host "Registered    : $($taskStatus.Registered)"
            if ($taskStatus.Registered) {
                Write-Host "State         : $($taskStatus.State)"
                Write-Host "Next run      : $($taskStatus.NextRun)"
                Write-Host "Last run      : $($taskStatus.LastRun)"
                Write-Host "Last result   : $($taskStatus.LastResult)"
            }

            if (Test-UpdateNeeded -Installed $installed -Release $release) {
                Write-Host ""
                Write-Host "Update available: $($release.VersionText)" -ForegroundColor Yellow
            }
            else {
                Write-Host ""
                Write-Host "Already up to date." -ForegroundColor Green
            }
            exit 0
        }
    }
}
catch {
    $message = $_.Exception.Message
    if ($paths -and $paths.Logs) {
        Write-UpdaterLog -LogDir $paths.Logs -Level ERROR -Message $message
    }
    else {
        Write-Host "ERROR: $message" -ForegroundColor Red
    }
    exit 1
}
