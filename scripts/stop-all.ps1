#Requires -Version 5.1
param([switch]$IncludeDocker)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig
Stop-LandcheckBackend -Cfg $cfg
if ($IncludeDocker) { Stop-LandcheckDocker -Cfg $cfg }
Write-Ok '已停止（默认仅停后端 JAR；加 -IncludeDocker 同时停 Docker）'
