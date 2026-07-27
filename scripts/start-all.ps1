#Requires -Version 5.1
<#
.SYNOPSIS
  启动 Docker + 后端 JAR。
.PARAMETER SkipOcrWait
  不等待 OCR health（日常重启可加快；OCR 会在后台 warmup）。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1
  powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1 -SkipOcrWait
#>
[CmdletBinding()]
param([switch]$SkipOcrWait)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig
if ($SkipOcrWait) {
    Ensure-LandcheckDocker -Cfg $cfg
}
else {
    Ensure-LandcheckDocker -Cfg $cfg -WaitOcr
}
Start-LandcheckBackend -Cfg $cfg
Wait-BackendHealthy -Cfg $cfg
Wait-ProxyHealthy -Cfg $cfg
Write-Ok "全部就绪: http://localhost:$($cfg.PROXY_PORT)/"
