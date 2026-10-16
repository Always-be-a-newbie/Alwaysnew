$ErrorActionPreference = 'Stop'

$files = @(
    '/workspace/lib/Get-LatestRelease.ps1',
    '/workspace/lib/Get-InstalledBlender.ps1',
    '/workspace/lib/Install-Blender.ps1',
    '/workspace/lib/Register-UpdateTask.ps1',
    '/workspace/blender-updater.ps1'
)

foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "FAIL $f"
        $errors | ForEach-Object { Write-Host $_.ToString() }
        exit 1
    }
    Write-Host "OK   $f"
}

. /workspace/lib/Get-LatestRelease.ps1

$rootHtml = @'
<a href="Blender4.5/">Blender4.5/</a>
<a href="Blender5.1/">Blender5.1/</a>
<a href="Blender5.2/">Blender5.2/</a>
<a href="BlenderBenchmark2.0/">BlenderBenchmark2.0/</a>
'@

$seriesHtml = @'
<a href="blender-5.2.0-windows-x64.msi">blender-5.2.0-windows-x64.msi</a>
<a href="blender-5.2.1-windows-x64.msi">blender-5.2.1-windows-x64.msi</a>
<a href="blender-5.2.2-windows-x64.msi">blender-5.2.2-windows-x64.msi</a>
<a href="blender-5.2.2-windows-arm64.msi">blender-5.2.2-windows-arm64.msi</a>
<a href="blender-5.2.2.sha256">blender-5.2.2.sha256</a>
'@

$v = ConvertTo-BlenderVersion '5.2.2'
if ($v.ToString() -ne '5.2.2') { throw "version parse failed: $v" }

$dirMatches = [regex]::Matches($rootHtml, 'href=["'']?(Blender(\d+)\.(\d+)/)["'']?', 'IgnoreCase')
$series = foreach ($m in $dirMatches) {
    [pscustomobject]@{
        Name  = $m.Groups[1].Value.TrimEnd('/')
        Major = [int]$m.Groups[2].Value
        Minor = [int]$m.Groups[3].Value
    }
}
$latest = $series | Sort-Object Major, Minor -Descending | Select-Object -First 1
if ($latest.Name -ne 'Blender5.2') { throw "series pick failed: $($latest.Name)" }

$Architecture = 'windows-x64'
$filePattern = "blender-(\d+\.\d+\.\d+)-$([regex]::Escape($Architecture))\.msi"
$fileMatches = [regex]::Matches($seriesHtml, "href=[`"']?($filePattern)[`"']?", 'IgnoreCase')
$candidates = foreach ($m in $fileMatches) {
    [pscustomobject]@{
        FileName = $m.Groups[1].Value
        Version  = (ConvertTo-BlenderVersion $m.Groups[2].Value)
    }
}
$pick = $candidates | Sort-Object Version -Descending | Select-Object -First 1
if ($pick.FileName -ne 'blender-5.2.2-windows-x64.msi') { throw "file pick failed: $($pick.FileName)" }

$sha = @'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  blender-5.2.2-windows-x64.msi
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  blender-5.2.2-windows-arm64.msi
'@
$found = $null
foreach ($line in ($sha -split "`r?`n")) {
    if ($line -match '^\s*([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$') {
        $name = Split-Path -Path $Matches[2].Trim() -Leaf
        if ($name -ieq 'blender-5.2.2-windows-x64.msi') {
            $found = $Matches[1]
            break
        }
    }
}
if ($found -ne 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') {
    throw 'sha parse failed'
}

# Config load smoke test (dot-source helpers used by main)
. /workspace/lib/Install-Blender.ps1
$env:LOCALAPPDATA = '/tmp/alwaysnew-localappdata'
$paths = Get-UpdaterPaths -Config @{
    DataRoot = '%LOCALAPPDATA%\Alwaysnew\BlenderUpdater'
    CacheDir = '%LOCALAPPDATA%\Alwaysnew\BlenderUpdater\cache'
    LogDir   = '%LOCALAPPDATA%\Alwaysnew\BlenderUpdater\logs'
}
if (-not (Test-Path -LiteralPath $paths.Cache)) { throw 'cache dir not created' }
Write-UpdaterLog -LogDir $paths.Logs -Message 'validation ok'

Write-Host 'Logic tests passed'
