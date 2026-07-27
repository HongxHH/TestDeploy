#Requires -Version 5.1
<#
.SYNOPSIS
  Stop backend then restart Docker/backend. Used by restart.bat.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

$exitCode = 1
$mutex = $null
try {
    $mutex = Enter-LandcheckOpsLock -Operation 'restart'
    $cfg = Import-DeployConfig

    Write-Host '========================================' -ForegroundColor White
    Write-Host ' landcheck restart' -ForegroundColor White
    Write-Host '========================================' -ForegroundColor White

    Write-Step 'Stop backend'
    Stop-LandcheckBackend -Cfg $cfg

    & "$PSScriptRoot\start-all.ps1"
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "start-all failed (exit=$LASTEXITCODE)"
    }

    Write-Host ''
    Write-Ok "Restart done: http://localhost:$($cfg.PROXY_PORT)/"
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