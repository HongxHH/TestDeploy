#Requires -Version 5.1
<#
.SYNOPSIS
  创建/更新 Conda 环境 SR（PDF 预处理依赖）。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\setup-conda.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig
$envFile = Join-Path $cfg.DEPLOY_ROOT 'conda\environment.yml'

if (-not (Test-Path $envFile)) {
    throw "缺少 $envFile"
}
if (-not (Test-CommandExists conda)) {
    throw '未找到 conda，请先安装 Miniconda/Anaconda 并加入 PATH'
}

function Test-CondaSrReady {
    $check = @'
import fitz, cv2, numpy, PIL, scipy
print("OK")
'@
    $tmp = Join-Path $env:TEMP "landcheck-conda-check.py"
    Set-Content -Path $tmp -Value $check -Encoding UTF8
    try {
        $out = cmd /c "conda run -n SR python ""$tmp"" 2>nul"
        return ($out -match 'OK')
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Step '检查 Conda 环境 SR'
$existing = cmd /c "conda env list" 2>&1 | Out-String
$hasSr = ($existing -match '(?m)^SR\s')

if ($hasSr -and (Test-CondaSrReady)) {
    Write-Ok 'Conda 环境 SR 已存在且依赖完整，跳过 create/update'
    exit 0
}

if ($hasSr) {
    Write-Host '环境 SR 已存在但依赖不完整，执行 update...' -ForegroundColor DarkGray
    $env:CONDA_ALWAYS_YES = 'true'
    $null = Invoke-External -FilePath 'conda' -ArgumentList @('env', 'update', '-n', 'SR', '-f', $envFile, '--prune')
}
else {
    Write-Step '创建 Conda 环境 SR'
    $null = Invoke-External -FilePath 'conda' -ArgumentList @('env', 'create', '-f', $envFile, '-y')
}

if (-not (Test-CondaSrReady)) {
    throw 'Conda SR 环境验证失败，请手动执行: conda env update -n SR -f conda\environment.yml'
}
Write-Ok 'Conda 环境 SR 就绪（后端 pdf_preprocessor.py 会使用此环境）'
