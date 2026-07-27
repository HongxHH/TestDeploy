#Requires -Version 5.1
<#
.SYNOPSIS
  Enable autostart (login + fixed 2 min delay). Used by enable-autostart.bat.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

# Elevate first, then take lock (avoid parent holding lock while child elevates)
Request-LandcheckAdminElevation -ScriptPath $PSCommandPath | Out-Null

$exitCode = 1
$mutex = $null
try {
    $mutex = Enter-LandcheckOpsLock -Operation 'enable-autostart'
    Write-Host '========================================' -ForegroundColor White
    Write-Host ' landcheck enable autostart (delay 2 min)' -ForegroundColor White
    Write-Host '========================================' -ForegroundColor White

    & "$PSScriptRoot\install-autostart.ps1"
    Write-Ok 'Autostart enabled'
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