function Get-UpdaterPaths {
    param(
        [hashtable]$Config
    )

    $root = if ($Config -and $Config.DataRoot) {
        [Environment]::ExpandEnvironmentVariables($Config.DataRoot)
    }
    else {
        Join-Path $env:LOCALAPPDATA 'Alwaysnew\BlenderUpdater'
    }

    $cache = if ($Config -and $Config.CacheDir) {
        [Environment]::ExpandEnvironmentVariables($Config.CacheDir)
    }
    else {
        Join-Path $root 'cache'
    }

    $logs = if ($Config -and $Config.LogDir) {
        [Environment]::ExpandEnvironmentVariables($Config.LogDir)
    }
    else {
        Join-Path $root 'logs'
    }

    foreach ($path in @($root, $cache, $logs)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    return [pscustomobject]@{
        Root  = $root
        Cache = $cache
        Logs  = $logs
    }
}

function Write-UpdaterLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$LogDir,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line

    if ($LogDir) {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        $logFile = Join-Path $LogDir ("blender-updater-{0:yyyyMMdd}.log" -f (Get-Date))
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
}

function Test-FileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return ($actual -eq $ExpectedSha256.ToLowerInvariant())
}

function Install-BlenderRelease {
    <#
    .SYNOPSIS
        Download, verify, and silently install a Blender MSI release.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Release,
        [hashtable]$Config,
        [switch]$WhatIf,
        [switch]$Force
    )

    $paths = Get-UpdaterPaths -Config $Config
    $msiPath = Join-Path $paths.Cache $Release.FileName

    Write-UpdaterLog -LogDir $paths.Logs -Message "Resolving SHA256 for $($Release.FileName)"
    $expectedSha = Get-BlenderReleaseSha256 -Sha256Url $Release.Sha256Url -FileName $Release.FileName

    $needDownload = $true
    if ((Test-Path -LiteralPath $msiPath) -and -not $Force) {
        if (Test-FileSha256 -Path $msiPath -ExpectedSha256 $expectedSha) {
            $needDownload = $false
            Write-UpdaterLog -LogDir $paths.Logs -Message "Using cached MSI: $msiPath"
        }
        else {
            Write-UpdaterLog -LogDir $paths.Logs -Level WARN -Message "Cached MSI checksum mismatch; re-downloading"
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($needDownload) {
        if ($WhatIf) {
            Write-UpdaterLog -LogDir $paths.Logs -Message "WhatIf: would download $($Release.DownloadUrl) -> $msiPath"
        }
        else {
            Write-UpdaterLog -LogDir $paths.Logs -Message "Downloading $($Release.DownloadUrl)"
            Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 600
            if (-not (Test-FileSha256 -Path $msiPath -ExpectedSha256 $expectedSha)) {
                throw "Downloaded file failed SHA256 verification: $msiPath"
            }
            Write-UpdaterLog -LogDir $paths.Logs -Message "SHA256 verified for $($Release.FileName)"
        }
    }

    $msiexecArgs = "/i `"$msiPath`" /qn /norestart"
    if ($WhatIf) {
        Write-UpdaterLog -LogDir $paths.Logs -Message "WhatIf: would run msiexec.exe $msiexecArgs"
        return [pscustomobject]@{
            Success     = $true
            Version     = $Release.VersionText
            MsiPath     = $msiPath
            ExitCode    = 0
            WhatIf      = $true
        }
    }

    Write-UpdaterLog -LogDir $paths.Logs -Message "Installing via msiexec (silent)"
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiexecArgs -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode

    # 0 = success, 3010 = success reboot required
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        throw "msiexec failed with exit code $exitCode"
    }

    Write-UpdaterLog -LogDir $paths.Logs -Message "Install finished (exit code $exitCode), version $($Release.VersionText)"
    return [pscustomobject]@{
        Success  = $true
        Version  = $Release.VersionText
        MsiPath  = $msiPath
        ExitCode = $exitCode
        WhatIf   = $false
    }
}
