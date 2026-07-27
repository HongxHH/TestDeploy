#Requires -Version 5.1
<#
.SYNOPSIS
  Disable autostart scheduled task. Used by disable-autostart.bat.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

# Idempotent fast path: nothing installed -> success, no UAC
if (-not (Test-LandcheckAutostartInstalled)) {
    Write-Ok 'Autostart task not found; nothing to cancel'
    Write-Host 'Note: Docker Desktop "Start when you sign in" is separate and unchanged.' -ForegroundColor DarkGray
    exit 0
}

try {
    # Elevate first, then take lock
    Request-LandcheckAdminElevation -ScriptPath $PSCommandPath | Out-Null
}
catch {
    Write-ErrMsg "Admin elevation failed (UAC cancelled or blocked): $($_.Exception.Message)"
    exit 1
}

$exitCode = 1
$mutex = $null
try {
    $mutex = Enter-LandcheckOpsLock -Operation 'disable-autostart'
    Write-Host '========================================' -ForegroundColor White
    Write-Host ' landcheck disable autostart' -ForegroundColor White
    Write-Host '========================================' -ForegroundColor White

    $result = Remove-LandcheckAutostartTask
    if ($result.Removed) {
        Write-Ok "Removed scheduled task: $($result.TaskName)"
    }
    else {
        Write-Ok "Autostart task not found; nothing to cancel"
    }

    Write-Host 'Note: Docker Desktop "Start when you sign in" must be changed in Docker settings manually.' -ForegroundColor DarkGray
    $exitCode = 0
}
catch {
    Write-ErrMsg $_.Exception.Message
    $exitCode = 1
}
finally {
    Exit-LandcheckOpsLock $mutex
}
exit $exitCode