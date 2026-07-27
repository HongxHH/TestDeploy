#Requires -Version 5.1
<#
.SYNOPSIS
  Remove landcheck Windows autostart scheduled task.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\uninstall-autostart.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"

$result = Remove-LandcheckAutostartTask
if (-not $result.Existed) {
    Write-WarnMsg "task not found: $($result.TaskName)"
    exit 0
}

Write-Ok "removed scheduled task: $($result.TaskName)"
Write-Host 'Docker containers may still start with Docker Desktop; backend JAR will not auto-start' -ForegroundColor DarkGray