#Requires -Version 5.1
<#
.SYNOPSIS
  Register Windows scheduled task: start landcheck 2 minutes after user logon (delay fixed at 2).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
#>
[CmdletBinding()]
param(
    [string]$UserName = $env:USERNAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"

# Fixed delay; do not change
$DelayMinutes = 2

$cfg = Import-DeployConfig
$taskName = Get-LandcheckAutostartTaskName
$bootScript = Join-Path $PSScriptRoot 'boot-start.ps1'
$root = $cfg.DEPLOY_ROOT

if (-not (Test-Path $bootScript)) { throw "missing $bootScript" }
if (-not (Test-Path (Join-Path $cfg.DEPLOY_BACKEND_DIR 'lc-start.jar'))) {
    Write-WarnMsg 'JAR not found; run scripts\setup.ps1 first'
}

Write-Host "[landcheck] install autostart task" -ForegroundColor White
Write-Host "  root: $root" -ForegroundColor DarkGray
Write-Host "  user: $UserName  delay: ${DelayMinutes}m (fixed)" -ForegroundColor DarkGray

$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootScript`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$trigger.Delay = "PT${DelayMinutes}M"

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 10)

$principal = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Limited

$registered = $false
if (Test-LandcheckAutostartInstalled) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null
    Write-WarnMsg "replaced existing task: $taskName"
}

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Description 'landcheck autostart on user logon (delay 2 min)' `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal -ErrorAction Stop | Out-Null
    $registered = $true
}
catch {
    Write-WarnMsg "Register-ScheduledTask failed: $($_.Exception.Message)"
    Write-Host '  trying schtasks fallback...' -ForegroundColor DarkGray
}

if (-not $registered) {
    $tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bootScript + '"'
    $schCmd = 'schtasks /Create /TN "' + $taskName + '" /TR "' + $tr + '" /SC ONLOGON /RL LIMITED /F'
    $schCmd += ' /DELAY 0002:00'
    cmd /c $schCmd
    if ($LASTEXITCODE -ne 0) {
        Write-ErrMsg "auto register failed (exit $LASTEXITCODE, access denied is common)"
        Write-Host ''
        Write-Host 'Run as Administrator (or use 设置开机自启.bat), or create task manually:' -ForegroundColor Yellow
        Write-Host '  Task Scheduler -> Create Task' -ForegroundColor White
        Write-Host '  Trigger: At logon, delay 2 minute(s)' -ForegroundColor White
        Write-Host '  Action: Start a program' -ForegroundColor White
        Write-Host '    Program: powershell.exe' -ForegroundColor White
        Write-Host "    Args:    -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootScript`"" -ForegroundColor White
        Write-Host "    Start in: $root" -ForegroundColor White
        throw "failed to register scheduled task (exit $LASTEXITCODE)"
    }
    $registered = $true
}

if (-not $registered) { throw 'failed to register autostart task' }

Write-Ok "scheduled task registered: $taskName (login + 2 min)"
Write-Host ""
Write-Host "One-time checklist:" -ForegroundColor Yellow
Write-Host "  1. Docker Desktop -> Settings -> Start when you sign in" -ForegroundColor White
Write-Host "  2. Windows auto-logon, or someone logs in after reboot" -ForegroundColor White
Write-Host "  3. Check logs\boot-start.log after reboot" -ForegroundColor White
Write-Host ""
Write-Host "Disable: 取消开机自启.bat  or  scripts\uninstall-autostart.ps1" -ForegroundColor DarkGray