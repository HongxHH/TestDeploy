#Requires -Version 5.1
<#
.SYNOPSIS
  移除 landcheck Windows 开机自启计划任务。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\uninstall-autostart.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"

$taskName = Get-LandcheckAutostartTaskName
if (-not (Test-LandcheckAutostartInstalled)) {
    Write-WarnMsg "task not found: $taskName"
    exit 0
}

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
schtasks /Delete /TN $taskName /F 2>$null | Out-Null
Write-Ok "已移除计划任务: $taskName"
Write-Host 'Docker 容器仍可能随 Docker Desktop 自动拉起；后端 JAR 不再自动启动' -ForegroundColor DarkGray
