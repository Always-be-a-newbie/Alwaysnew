function Get-BlenderVersionFromExe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExePath
    )

    if (-not (Test-Path -LiteralPath $ExePath)) {
        return $null
    }

    try {
        $output = & $ExePath --version 2>&1 | Out-String
        if ($output -match 'Blender\s+(\d+\.\d+(?:\.\d+)?)') {
            return ConvertTo-BlenderVersion -VersionText $Matches[1]
        }
    }
    catch {
        # Fall through to file version info
    }

    try {
        $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath).FileVersion
        if (-not [string]::IsNullOrWhiteSpace($fileVersion)) {
            return ConvertTo-BlenderVersion -VersionText $fileVersion
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-BlenderInstallCandidates {
    param(
        [string]$ConfiguredInstallPath
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredInstallPath)) {
        $configuredExe = Join-Path $ConfiguredInstallPath 'blender.exe'
        $candidates.Add($configuredExe)
    }

    $programFilesRoots = @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($root in $programFilesRoots) {
        $foundation = Join-Path $root 'Blender Foundation'
        if (Test-Path -LiteralPath $foundation) {
            Get-ChildItem -LiteralPath $foundation -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'Blender*' } |
                ForEach-Object {
                    $candidates.Add((Join-Path $_.FullName 'blender.exe'))
                }
        }

        # Some installs land directly under Program Files\Blender *
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Blender *' -or $_.Name -eq 'Blender' } |
            ForEach-Object {
                $candidates.Add((Join-Path $_.FullName 'blender.exe'))
            }
    }

    return $candidates | Select-Object -Unique
}

function Get-BlenderFromUninstallRegistry {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entries = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                $_.DisplayName -match 'Blender' -and
                $_.DisplayName -notmatch 'Benchmark'
            }
    }

    if (-not $entries) {
        return $null
    }

    $best = $null
    foreach ($entry in $entries) {
        $version = $null
        if ($entry.DisplayVersion) {
            $version = ConvertTo-BlenderVersion -VersionText ([string]$entry.DisplayVersion)
        }

        $exePath = $null
        if ($entry.InstallLocation) {
            $candidate = Join-Path $entry.InstallLocation 'blender.exe'
            if (Test-Path -LiteralPath $candidate) {
                $exePath = $candidate
                if ($null -eq $version) {
                    $version = Get-BlenderVersionFromExe -ExePath $exePath
                }
            }
        }

        if ($null -eq $version -and -not $exePath) {
            continue
        }

        $item = [pscustomobject]@{
            Version      = $version
            VersionText  = if ($version) { $version.ToString() } else { $null }
            ExePath      = $exePath
            InstallPath  = $entry.InstallLocation
            DisplayName  = $entry.DisplayName
            Source       = 'Registry'
            IsSteam      = ($entry.DisplayName -match 'Steam' -or ($exePath -and $exePath -match '\\Steam\\'))
        }

        if ($null -eq $best -or ($item.Version -and $best.Version -and $item.Version -gt $best.Version) -or ($item.Version -and -not $best.Version)) {
            $best = $item
        }
    }

    return $best
}

function Get-InstalledBlender {
    <#
    .SYNOPSIS
        Detect the currently installed official Blender build on Windows.
    #>
    param(
        [string]$ConfiguredInstallPath
    )

    foreach ($exe in (Get-BlenderInstallCandidates -ConfiguredInstallPath $ConfiguredInstallPath)) {
        if (-not (Test-Path -LiteralPath $exe)) {
            continue
        }

        $version = Get-BlenderVersionFromExe -ExePath $exe
        $isSteam = ($exe -match '\\Steam\\')
        return [pscustomobject]@{
            Version     = $version
            VersionText = if ($version) { $version.ToString() } else { 'unknown' }
            ExePath     = $exe
            InstallPath = Split-Path -Parent $exe
            DisplayName = 'Blender'
            Source      = 'FileSystem'
            IsSteam     = [bool]$isSteam
        }
    }

    $fromRegistry = Get-BlenderFromUninstallRegistry
    if ($fromRegistry) {
        return $fromRegistry
    }

    return [pscustomobject]@{
        Version     = $null
        VersionText = $null
        ExePath     = $null
        InstallPath = $null
        DisplayName = $null
        Source      = 'NotFound'
        IsSteam     = $false
    }
}
