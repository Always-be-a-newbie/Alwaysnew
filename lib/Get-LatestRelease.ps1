function Get-BlenderWindowsArch {
    <#
    .SYNOPSIS
        Map the current Windows machine to a Blender release architecture tag.
    #>
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        switch ("$arch") {
            'X64' { return 'windows-x64' }
            'Arm64' { return 'windows-arm64' }
        }
    }
    catch {
        # Windows PowerShell 5.1 / older runtimes
    }

    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        return 'windows-arm64'
    }

    return 'windows-x64'
}

function Get-RemoteText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 60
    return [string]$response.Content
}

function ConvertTo-BlenderVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    $clean = ($VersionText -replace '[^\d\.]', '').Trim('.')
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    $parts = $clean.Split('.') | Where-Object { $_ -match '^\d+$' }
    if ($parts.Count -lt 2) {
        return $null
    }

    while ($parts.Count -lt 3) {
        $parts += '0'
    }

    return [version](($parts[0..2]) -join '.')
}

function Get-BlenderReleaseSeries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseRootUrl
    )

    $html = Get-RemoteText -Uri $ReleaseRootUrl
    $dirMatches = [regex]::Matches($html, 'href=["'']?(Blender(\d+)\.(\d+)/)["'']?', 'IgnoreCase')
    if ($dirMatches.Count -eq 0) {
        throw "Unable to parse Blender release directories from $ReleaseRootUrl"
    }

    $series = foreach ($m in $dirMatches) {
        [pscustomobject]@{
            Name    = $m.Groups[1].Value.TrimEnd('/')
            Major   = [int]$m.Groups[2].Value
            Minor   = [int]$m.Groups[3].Value
            Version = [version]("$($m.Groups[2].Value).$($m.Groups[3].Value).0")
            Url     = ($ReleaseRootUrl.TrimEnd('/') + '/' + $m.Groups[1].Value)
        }
    }

    $series |
        Sort-Object -Property Major, Minor -Descending |
        Select-Object -First 1
}

function Get-LatestBlenderRelease {
    <#
    .SYNOPSIS
        Resolve the newest official stable Windows MSI from download.blender.org.
    #>
    param(
        [string]$ReleaseRootUrl = 'https://download.blender.org/release/',
        [string]$Architecture
    )

    if ([string]::IsNullOrWhiteSpace($Architecture)) {
        $Architecture = Get-BlenderWindowsArch
    }

    $latestSeries = Get-BlenderReleaseSeries -ReleaseRootUrl $ReleaseRootUrl
    $seriesHtml = Get-RemoteText -Uri $latestSeries.Url

    $filePattern = "blender-(\d+\.\d+\.\d+)-$([regex]::Escape($Architecture))\.msi"
    $fileMatches = [regex]::Matches($seriesHtml, "href=[`"']?($filePattern)[`"']?", 'IgnoreCase')
    if ($fileMatches.Count -eq 0) {
        throw "No MSI found for architecture '$Architecture' under $($latestSeries.Url)"
    }

    $candidates = foreach ($m in $fileMatches) {
        $fileName = $m.Groups[1].Value
        $version = ConvertTo-BlenderVersion -VersionText $m.Groups[2].Value
        if ($null -eq $version) {
            continue
        }

        [pscustomobject]@{
            FileName     = $fileName
            Version      = $version
            VersionText  = $version.ToString()
            Architecture = $Architecture
            DownloadUrl  = ($latestSeries.Url.TrimEnd('/') + '/' + $fileName)
            Sha256Url    = ($latestSeries.Url.TrimEnd('/') + '/' + ("blender-$($version.ToString()).sha256"))
            SeriesName   = $latestSeries.Name
            SeriesUrl    = $latestSeries.Url
        }
    }

    $latest = $candidates | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($null -eq $latest) {
        throw "Failed to resolve a latest Blender release for $Architecture"
    }

    return $latest
}

function Get-BlenderReleaseSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sha256Url,
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $content = Get-RemoteText -Uri $Sha256Url
    foreach ($line in ($content -split "`r?`n")) {
        if ($line -match '^\s*([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$') {
            $hash = $Matches[1].ToLowerInvariant()
            $name = Split-Path -Path $Matches[2].Trim() -Leaf
            if ($name -ieq $FileName) {
                return $hash
            }
        }
    }

    throw "SHA256 for '$FileName' not found in $Sha256Url"
}
