#Requires -Version 5.1
<#
.SYNOPSIS
  从 Git 拉取源码 -> 构建 -> 拷贝产物 -> 删除源码 -> 重启服务。
.PARAMETER Force
  即使 commit 未变化也重新构建部署。
.PARAMETER SkipStart
  只构建产物，不启动后端和反代。
.PARAMETER BackendOnly
  仅部署后端。
.PARAMETER FrontendOnly
  仅部署前端。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipStart,
    [switch]$BackendOnly,
    [switch]$FrontendOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

if ($BackendOnly -and $FrontendOnly) {
    throw '不能同时指定 -BackendOnly 与 -FrontendOnly'
}

$cfg = Import-DeployConfig
Ensure-DeployDirs $cfg

$deployBackend = -not $FrontendOnly
$deployFrontend = -not $BackendOnly

function Prepare-SourceTree {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$RepoUrl
    )

    $dest = Join-Path $cfg.WORK_DIR $Kind
    if (Test-Path $dest) {
        Remove-Item $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    Write-Step "$Kind : git clone --depth 1 ($RepoUrl)"
    $null = Invoke-External -FilePath 'git' -ArgumentList @(
        'clone', '--depth', '1', '--branch', $cfg.GIT_BRANCH, $RepoUrl, $dest
    )
    $short = Get-GitShortRev -RepoPath $dest
    Push-Location $dest
    try { $full = (git rev-parse HEAD).Trim() } finally { Pop-Location }
    return [hashtable]@{ SrcPath = $dest; short = $short; full = $full; source = $RepoUrl }
}

function Get-SourceTreePath {
    param([Parameter(Mandatory = $true)][hashtable]$Tree)
    if (-not $Tree.ContainsKey('SrcPath')) { throw '源码树缺少 SrcPath' }
    $p = [string]$Tree['SrcPath'].Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { throw '源码路径为空' }
    if (-not (Test-Path $p)) { throw "源码目录不存在: $p" }
    return $p
}

function Build-Backend {
    param([Parameter(Mandatory = $true)][string]$SourcePath)
    $SourcePath = $SourcePath.Trim()
    Assert-BackendPdfPreprocessor -SourcePath $SourcePath
    Write-Step '构建后端 JAR (mvnw.cmd)'
    $mvnw = Join-Path $SourcePath 'mvnw.cmd'
    if (-not (Test-Path $mvnw)) { throw "未找到 mvnw.cmd: $mvnw" }

    $null = Invoke-External -FilePath $mvnw -ArgumentList @(
        '-pl', 'lc-start', '-am', 'clean', 'package', '-DskipTests'
    ) -WorkingDirectory $SourcePath

    $jar = Get-ChildItem (Join-Path $SourcePath 'lc-start\target\lc-start-*.jar') |
        Where-Object { $_.Name -notmatch 'original' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $jar) { throw '未找到 lc-start-*.jar 构建产物' }

    $targetJar = Join-Path $cfg.DEPLOY_BACKEND_DIR 'lc-start.jar'
    Copy-Item $jar.FullName $targetJar -Force
    if (-not (Test-JarContainsResource -JarPath $targetJar -ResourceName 'pdf_preprocessor.py')) {
        throw 'JAR 内缺少 pdf_preprocessor.py，请确认后端 Git 仓库已包含该文件并重新构建'
    }
    Write-Ok "JAR 已部署: $targetJar"
}

function Build-Frontend {
    param([Parameter(Mandatory = $true)][string]$SourcePath)
    $SourcePath = $SourcePath.Trim()
    Write-Step '构建前端 (npm ci + npm run build)'
    $null = Invoke-External -FilePath 'npm.cmd' -ArgumentList @('ci') -WorkingDirectory $SourcePath
    $null = Invoke-External -FilePath 'npm.cmd' -ArgumentList @('run', 'build') -WorkingDirectory $SourcePath

    $dist = Join-Path $SourcePath 'dist'
    if (-not (Test-Path $dist)) { throw '未找到 dist 目录' }

    if (Test-Path $cfg.DEPLOY_FRONTEND_DIR) {
        Remove-Item $cfg.DEPLOY_FRONTEND_DIR -Recurse -Force
    }
    New-Item -ItemType Directory -Path $cfg.DEPLOY_FRONTEND_DIR -Force | Out-Null
    $rc = Start-Process -FilePath 'robocopy' -ArgumentList @($dist, $cfg.DEPLOY_FRONTEND_DIR, '/MIR') -NoNewWindow -Wait -PassThru
    if ($rc.ExitCode -gt 7) {
        throw "复制 dist 失败, exit=$($rc.ExitCode)"
    }
    Write-Ok "前端静态文件已部署: $($cfg.DEPLOY_FRONTEND_DIR)"
}

Write-Host 'landcheck 一键部署' -ForegroundColor White
Write-Host "根目录: $($cfg.DEPLOY_ROOT)" -ForegroundColor DarkGray

if (-not $Force) {
    $updateScript = Join-Path $PSScriptRoot 'check-updates.ps1'
    & $updateScript -Json | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok '版本未变化，跳过部署（使用 -Force 强制重建）'
        exit 0
    }
    if ($LASTEXITCODE -eq 1) {
        throw '更新检测失败，请检查 deploy.env 或 Git 网络'
    }
}

try {
    if ($deployBackend) {
        $backendTree = Prepare-SourceTree -Kind 'backend' -RepoUrl $cfg.BACKEND_REPO_URL
        Build-Backend -SourcePath (Get-SourceTreePath -Tree $backendTree)
        Save-DeployedMeta -MetaDir $cfg.DEPLOY_META_DIR -Name 'backend' -Commit $backendTree['short'] -FullCommit $backendTree['full'] -Source $backendTree['source']
    }

    if ($deployFrontend) {
        $frontendTree = Prepare-SourceTree -Kind 'frontend' -RepoUrl $cfg.FRONTEND_REPO_URL
        Build-Frontend -SourcePath (Get-SourceTreePath -Tree $frontendTree)
        Save-DeployedMeta -MetaDir $cfg.DEPLOY_META_DIR -Name 'frontend' -Commit $frontendTree['short'] -FullCommit $frontendTree['full'] -Source $frontendTree['source']
    }
}
finally {
    Write-Step '清理临时源码 (.work)'
    if (Test-Path $cfg.WORK_DIR) {
        Remove-Item $cfg.WORK_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Ok '源码已删除，仅保留 deploy/ 产物'

if (-not $SkipStart) {
    Ensure-LandcheckDocker -Cfg $cfg -WaitOcr
    if ($deployBackend) {
        Start-LandcheckBackend -Cfg $cfg
        Wait-BackendHealthy -Cfg $cfg
    }
    Wait-ProxyHealthy -Cfg $cfg
}

Write-Host ''
Write-Ok '部署完成'
Write-Host "  前端: http://localhost:$($cfg.PROXY_PORT)/" -ForegroundColor Green
Write-Host "  后端: http://localhost:$($cfg.BACKEND_PORT)/" -ForegroundColor Green
Write-Host "  日志: $($cfg.LOG_DIR)" -ForegroundColor DarkGray
