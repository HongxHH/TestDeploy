#Requires -Version 5.1
<#
.SYNOPSIS
  Stop services, pull/rebuild frontend+backend, then start. Used by rebuild.bat.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

$exitCode = 1
$mutex = $null
try {
    $mutex = Enter-LandcheckOpsLock -Operation 'rebuild'
    $cfg = Import-DeployConfig

    Write-Host '========================================' -ForegroundColor White
    Write-Host ' landcheck rebuild' -ForegroundColor White
    Write-Host '========================================' -ForegroundColor White

    Write-Step 'Stop backend (avoid JAR replace conflict)'
    Stop-LandcheckBackend -Cfg $cfg

    & "$PSScriptRoot\deploy.ps1"
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "deploy failed (exit=$LASTEXITCODE)"
    }

    Write-Host ''
    Write-Ok "Rebuild done: http://localhost:$($cfg.PROXY_PORT)/"
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