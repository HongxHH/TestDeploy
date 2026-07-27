#Requires -Version 5.1
<#
.SYNOPSIS
  启动 Docker + 后端 JAR（等待 OCR 就绪）。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig
Ensure-LandcheckDocker -Cfg $cfg -WaitOcr
Start-LandcheckBackend -Cfg $cfg
Wait-BackendHealthy -Cfg $cfg
Wait-ProxyHealthy -Cfg $cfg
Write-Ok "全部就绪: http://localhost:$($cfg.PROXY_PORT)/"
