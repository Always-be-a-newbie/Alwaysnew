$script:BlenderUpdaterTaskName = 'Alwaysnew-BlenderUpdater'

function Get-BlenderUpdaterTask {
    Get-ScheduledTask -TaskName $script:BlenderUpdaterTaskName -ErrorAction SilentlyContinue
}

function Register-BlenderUpdateTask {
    <#
    .SYNOPSIS
        Register a weekly Task Scheduler job that runs blender-updater.ps1 update.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpdaterScriptPath,
        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$DayOfWeek = 'Sunday',
        [string]$At = '10:00',
        [switch]$WhatIf
    )

    if (-not (Test-Path -LiteralPath $UpdaterScriptPath)) {
        throw "Updater script not found: $UpdaterScriptPath"
    }

    $resolvedScript = (Resolve-Path -LiteralPath $UpdaterScriptPath).Path
    $argument = "-NoProfile -ExecutionPolicy Bypass -File `"$resolvedScript`" update"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

    try {
        $time = [datetime]::ParseExact($At, @('H:mm', 'HH:mm', 'h:mm tt', 'hh:mm tt'), [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
    }
    catch {
        throw "Invalid -At time '$At'. Use HH:mm (e.g. 10:00)."
    }

    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $time
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

    if ($WhatIf) {
        Write-Host "WhatIf: would register scheduled task '$script:BlenderUpdaterTaskName' ($DayOfWeek at $At)"
        Write-Host "WhatIf: action powershell.exe $argument"
        return $null
    }

    $existing = Get-BlenderUpdaterTask
    if ($existing) {
        Unregister-ScheduledTask -TaskName $script:BlenderUpdaterTaskName -Confirm:$false
    }

    Register-ScheduledTask `
        -TaskName $script:BlenderUpdaterTaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description 'Alwaysnew: check blender.org and silently install the latest stable Blender MSI' `
        -Force | Out-Null

    return Get-BlenderUpdaterTask
}

function Unregister-BlenderUpdateTask {
    param(
        [switch]$WhatIf
    )

    $existing = Get-BlenderUpdaterTask
    if (-not $existing) {
        Write-Host "Scheduled task '$script:BlenderUpdaterTaskName' is not registered."
        return $false
    }

    if ($WhatIf) {
        Write-Host "WhatIf: would unregister scheduled task '$script:BlenderUpdaterTaskName'"
        return $true
    }

    Unregister-ScheduledTask -TaskName $script:BlenderUpdaterTaskName -Confirm:$false
    Write-Host "Removed scheduled task '$script:BlenderUpdaterTaskName'."
    return $true
}

function Get-BlenderUpdaterTaskStatus {
    $task = Get-BlenderUpdaterTask
    if (-not $task) {
        return [pscustomobject]@{
            Registered = $false
            TaskName   = $script:BlenderUpdaterTaskName
            State      = $null
            NextRun    = $null
            LastRun    = $null
            LastResult = $null
        }
    }

    $info = Get-ScheduledTaskInfo -TaskName $script:BlenderUpdaterTaskName -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        Registered = $true
        TaskName   = $script:BlenderUpdaterTaskName
        State      = [string]$task.State
        NextRun    = if ($info) { $info.NextRunTime } else { $null }
        LastRun    = if ($info) { $info.LastRunTime } else { $null }
        LastResult = if ($info) { $info.LastTaskResult } else { $null }
    }
}
