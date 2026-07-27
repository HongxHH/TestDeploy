#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-DeployRoot {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not (Test-Path (Join-Path $root 'deploy.env')) -and -not (Test-Path (Join-Path $root 'deploy.env.example'))) {
        throw "无法定位 TestDeploy 根目录: $root"
    }
    return $root
}

function Import-DeployConfig {
    $root = Get-DeployRoot
    $envFile = Join-Path $root 'deploy.env'
    if (-not (Test-Path $envFile)) {
        throw "缺少 deploy.env，请复制 deploy.env.example 为 deploy.env"
    }

    $cfg = [ordered]@{}
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim().Trim([char]0xFEFF)
        $cfg[$key] = $line.Substring($idx + 1).Trim()
    }

    foreach ($required in @('MONGO_DATA_DIR', 'BACKEND_PORT', 'PROXY_PORT', 'SPRING_PROFILE', 'GIT_BRANCH')) {
        if (-not $cfg.Contains($required) -or [string]::IsNullOrWhiteSpace([string]$cfg[$required])) {
            throw "deploy.env 缺少: $required"
        }
    }

    $cfg['DEPLOY_ROOT'] = $root
    $cfg['DEPLOY_ENV_FILE'] = $envFile
    $cfg['COMPOSE_FILE'] = Join-Path $root 'docker-compose.yml'
    $cfg['DEPLOY_BACKEND_DIR'] = Join-Path $root 'deploy\backend'
    $cfg['DEPLOY_FRONTEND_DIR'] = Join-Path $root 'deploy\frontend\dist'
    $cfg['DEPLOY_META_DIR'] = Join-Path $root 'deploy\meta'
    $cfg['LOG_DIR'] = if ($cfg['LANDCHECK_LOG_DIR']) { $cfg['LANDCHECK_LOG_DIR'] } else { Join-Path $root 'logs' }
    $cfg['WORK_DIR'] = Join-Path $root '.work'
    if (-not $cfg['BACKEND_REPO_URL']) { $cfg['BACKEND_REPO_URL'] = 'https://gitee.com/wqhshuaige/land-backend.git' }
    if (-not $cfg['FRONTEND_REPO_URL']) { $cfg['FRONTEND_REPO_URL'] = 'https://gitee.com/wqhshuaige/land-frontend.git' }
    return $cfg
}

function Get-LandcheckDockerContainerNames {
    return @(
        'mongodb'
        'landcheck-redis'
        'landcheck-rmqnamesrv'
        'landcheck-rmqbroker'
        'landcheck-proxy'
        'paddleocr-vlm-server'
        'paddleocr-vl-api'
    )
}

function Test-LandcheckDockerContainers {
    param([switch]$Quiet)
    $allOk = $true
    if (-not (Test-DockerEngineRunning)) {
        if (-not $Quiet) { Write-ErrMsg 'Docker 未运行（若已安装请启动 Docker Desktop）' }
        return $false
    }
    foreach ($name in (Get-LandcheckDockerContainerNames)) {
        $status = Get-DockerContainerStatus $name
        if ($status -eq 'running') {
            if (-not $Quiet) { Write-Ok "$name : running" }
        }
        else {
            $allOk = $false
            if (-not $Quiet) {
                Write-WarnMsg "$name : $(if ($status) { $status } else { '未启动' })"
            }
        }
    }
    return $allOk
}

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-WarnMsg([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrMsg([string]$Message) { Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Ensure-DeployDirs([hashtable]$Cfg) {
    foreach ($dir in @($Cfg['DEPLOY_BACKEND_DIR'], $Cfg['DEPLOY_FRONTEND_DIR'], $Cfg['DEPLOY_META_DIR'], $Cfg['LOG_DIR'], $Cfg['WORK_DIR'])) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}

function Get-GitShortRev {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    if (-not (Test-Path (Join-Path $RepoPath '.git'))) { return $null }
    Push-Location $RepoPath
    try { return (git rev-parse --short HEAD).Trim() } finally { Pop-Location }
}

function Get-RemoteShortRev {
    param([Parameter(Mandatory = $true)][string]$RepoUrl, [Parameter(Mandatory = $true)][string]$Branch)
    $hash = git ls-remote $RepoUrl "refs/heads/$Branch" 2>$null
    if (-not $hash) { return $null }
    $full = ($hash -split '\s+')[0]
    if ($full.Length -ge 7) { return $full.Substring(0, 7) }
    return $full
}

function Read-DeployedRev([string]$MetaFile) {
    if (-not (Test-Path $MetaFile)) { return $null }
    $line = Get-Content $MetaFile -TotalCount 1 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    return $line.Trim()
}

function Save-DeployedMeta {
    param(
        [Parameter(Mandatory = $true)][string]$MetaDir,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Commit,
        [string]$FullCommit = '',
        [string]$Source = ''
    )
    @(
        $Commit
        "deployed_at=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "full=$FullCommit"
        "source=$Source"
    ) | Set-Content -Path (Join-Path $MetaDir "$Name.deployed") -Encoding UTF8
}

function Test-CommandExists([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-JarContainsResource {
    param(
        [Parameter(Mandatory = $true)][string]$JarPath,
        [Parameter(Mandatory = $true)][string]$ResourceName
    )
    if (-not (Test-Path $JarPath)) { return $false }

    # 不依赖 PATH 中的 jar 命令（mvnw 能构建成功时 jar 未必在 PATH）
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $JarPath).Path)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match [regex]::Escape($ResourceName)) {
                return $true
            }
        }
        return $false
    }
    finally {
        $zip.Dispose()
    }
}

function Assert-BackendPdfPreprocessor {
    param([Parameter(Mandatory = $true)][string]$SourcePath)
    $scriptPath = Join-Path $SourcePath 'lc-start\src\main\resources\pdf_preprocessor.py'
    if (-not (Test-Path $scriptPath)) {
        throw "后端源码缺少 pdf_preprocessor.py（应在 lc-start/src/main/resources，且已提交 Git）"
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = '',
        [int[]]$AllowedExitCodes = @(0)
    )
    $psi = @{ FilePath = $FilePath; ArgumentList = $ArgumentList; NoNewWindow = $true; Wait = $true; PassThru = $true }
    if ($WorkingDirectory) { $psi['WorkingDirectory'] = $WorkingDirectory }
    $proc = Start-Process @psi
    if ($AllowedExitCodes -notcontains $proc.ExitCode) {
        throw "命令失败 (exit $($proc.ExitCode)): $FilePath $($ArgumentList -join ' ')"
    }
    return $proc
}

function Get-DockerContainerStatus([string]$Name) {
    # 容器不存在时 docker inspect 会写 stderr，PowerShell Stop 模式会当成异常
    $out = cmd /c "docker inspect -f ""{{.State.Status}}"" $Name 2>nul"
    if ([string]::IsNullOrWhiteSpace($out)) { return $null }
    return $out.Trim()
}

function Test-DockerEngineRunning {
    if (-not (Test-CommandExists docker)) { return $false }
    $v = cmd /c "docker version --format ""{{.Server.Version}}"" 2>nul"
    return -not [string]::IsNullOrWhiteSpace($v)
}

function Wait-DockerEngineReady {
    param([int]$TimeoutSec = 600)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-DockerEngineRunning) { return $true }
        Start-Sleep -Seconds 10
    }
    return $false
}

function Get-LandcheckAutostartTaskName { return 'LandcheckAutoStart' }

function Test-LandcheckAutostartInstalled {
    if (Get-ScheduledTask -TaskName (Get-LandcheckAutostartTaskName) -ErrorAction SilentlyContinue) {
        return $true
    }
    cmd /c "schtasks /Query /TN $(Get-LandcheckAutostartTaskName) >nul 2>nul"
    return ($LASTEXITCODE -eq 0)
}

function Test-MongoReplicaSetReady {
    $raw = cmd /c "docker exec mongodb mongosh --quiet --eval ""try{print(rs.status().ok)}catch(e){print(0)}"" 2>nul"
    if (-not $raw) { return $false }
    return ($raw.Trim() -eq '1')
}

function Ensure-MongoReplicaSet {
    if (-not ((Get-DockerContainerStatus 'mongodb') -eq 'running')) {
        Write-WarnMsg 'Mongo 容器未运行，跳过副本集检查'
        return
    }
    if (Test-MongoReplicaSetReady) {
        Write-Ok 'Mongo 副本集已就绪（拷贝 A 机数据集时通常已包含）'
        return
    }
    Write-Step 'Mongo 副本集未初始化，正在 rs.initiate（仅空库需要；拷贝数据集不应走到此步）'
    Invoke-External -FilePath 'docker' -ArgumentList @(
        'exec', 'mongodb', 'mongosh', '--eval',
        "rs.initiate({_id:'rs0', members:[{_id:0, host:'localhost:27017'}]})"
    ) -AllowedExitCodes @(0, 1)
    Start-Sleep -Seconds 5
    if (Test-MongoReplicaSetReady) { Write-Ok 'Mongo 副本集初始化完成' }
    else { Write-WarnMsg 'Mongo 副本集状态未确认，请检查 mongodb 容器日志' }
}

function Wait-DockerContainersRunning {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [int]$TimeoutSec = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $allRunning = $true
        foreach ($name in $Names) {
            if ((Get-DockerContainerStatus $name) -ne 'running') {
                $allRunning = $false
                break
            }
        }
        if ($allRunning) { return }
        Start-Sleep -Seconds 3
    }
    throw "Docker 容器启动超时: $($Names -join ', ')"
}

function Wait-OcrHealthy {
    param([int]$TimeoutSec = 600)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    Write-Step '等待 OCR 就绪 http://127.0.0.1:8080/health（首次可能 5~10 分钟）'
    while ((Get-Date) -lt $deadline) {
        if ((Get-DockerContainerStatus 'paddleocr-vlm-server') -ne 'running') {
            Start-Sleep -Seconds 5
            continue
        }
        try {
            $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/health' -UseBasicParsing -TimeoutSec 10
            if ($resp.StatusCode -eq 200) { Write-Ok 'OCR 就绪'; return }
        }
        catch { Start-Sleep -Seconds 10 }
    }
    throw 'OCR 超时，请检查 docker logs paddleocr-vlm-server / paddleocr-vl-api'
}

function Ensure-LandcheckDocker {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Cfg,
        [switch]$WaitOcr
    )
    if (-not (Test-Path $Cfg['COMPOSE_FILE'])) { throw '缺少 docker-compose.yml' }
    if (-not (Test-DockerEngineRunning)) {
        throw 'Docker 未运行，请先启动 Docker Desktop'
    }

    $required = Get-LandcheckDockerContainerNames
    $needUp = $false
    foreach ($name in $required) {
        $st = Get-DockerContainerStatus $name
        if ($st -ne 'running') {
            $needUp = $true
            if ($st) { Write-Host "  $name : $st -> 将重启" -ForegroundColor DarkYellow }
            else { Write-Host "  $name : 不存在 -> 将创建" -ForegroundColor DarkYellow }
        }
    }

    if ($needUp) {
        Write-Step '启动/更新 Docker 服务 (docker compose up -d)'
    }
    else {
        Write-Step 'Docker 服务已在运行，执行 compose up 确保配置最新'
    }

    foreach ($legacyName in @('landcheck-app-proxy')) {
        cmd /c "docker rm -f $legacyName 2>nul" | Out-Null
    }
    $null = Invoke-External -FilePath 'docker' -ArgumentList @(
        'compose', '--env-file', $Cfg['DEPLOY_ENV_FILE'], '-f', $Cfg['COMPOSE_FILE'], 'up', '-d'
    ) -WorkingDirectory $Cfg['DEPLOY_ROOT']

    Wait-DockerContainersRunning -Names $required -TimeoutSec 180
    Ensure-MongoReplicaSet
    if ($WaitOcr) { Wait-OcrHealthy }
    Write-Ok "Docker 就绪: http://localhost:$($Cfg['PROXY_PORT'])/"
}

function Stop-LandcheckDocker([hashtable]$Cfg) {
    if (-not (Test-Path $Cfg['COMPOSE_FILE'])) { return }
    Write-Step '停止 Docker 容器'
    $null = Invoke-External -FilePath 'docker' -ArgumentList @(
        'compose', '--env-file', $Cfg['DEPLOY_ENV_FILE'], '-f', $Cfg['COMPOSE_FILE'], 'down'
    ) -WorkingDirectory $Cfg['DEPLOY_ROOT'] -AllowedExitCodes @(0, 1)
    Write-Ok 'Docker 容器已停止'
}

function Stop-LandcheckBackend([hashtable]$Cfg) {
    $pidFile = Join-Path $Cfg['DEPLOY_BACKEND_DIR'] 'backend.pid'
    if (-not (Test-Path $pidFile)) { Write-WarnMsg '未找到 backend.pid'; return }
    $backendPid = [int](Get-Content $pidFile -TotalCount 1)
    if ($backendPid -le 0) { return }
    $proc = Get-Process -Id $backendPid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Step "停止后端 PID=$backendPid"
        Stop-Process -Id $backendPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Ok '后端已停止'
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Start-LandcheckBackend([hashtable]$Cfg) {
    $jar = Join-Path $Cfg['DEPLOY_BACKEND_DIR'] 'lc-start.jar'
    if (-not (Test-Path $jar)) { throw "未找到 JAR，请先 scripts\deploy.ps1" }
    Stop-LandcheckBackend -Cfg $Cfg

    $logOut = Join-Path $Cfg['LOG_DIR'] 'backend.stdout.log'
    $logErr = Join-Path $Cfg['LOG_DIR'] 'backend.stderr.log'
    Set-Item env:SPRING_PROFILES_ACTIVE $Cfg['SPRING_PROFILE']
    Set-Item env:LANDCHECK_LOG_DIR $Cfg['LOG_DIR']
    if ($Cfg['LANDCHECK_MONGODB_URI']) { Set-Item env:LANDCHECK_MONGODB_URI $Cfg['LANDCHECK_MONGODB_URI'] }
    if ($Cfg['LANDCHECK_REDIS_PASSWORD']) { Set-Item env:LANDCHECK_REDIS_PASSWORD $Cfg['LANDCHECK_REDIS_PASSWORD'] }
    if ($Cfg['LANDCHECK_LLM_API_KEY']) { Set-Item env:LANDCHECK_LLM_API_KEY $Cfg['LANDCHECK_LLM_API_KEY'] }

    Write-Step "启动后端 JAR (port=$($Cfg['BACKEND_PORT']))"
    $proc = Start-Process -FilePath (Get-Command java).Source -ArgumentList @(
        '-jar', $jar, "--server.port=$($Cfg['BACKEND_PORT'])"
    ) -WorkingDirectory $Cfg['DEPLOY_BACKEND_DIR'] -RedirectStandardOutput $logOut -RedirectStandardError $logErr -WindowStyle Hidden -PassThru
    $proc.Id | Set-Content (Join-Path $Cfg['DEPLOY_BACKEND_DIR'] 'backend.pid') -Encoding ASCII
    Write-Ok "后端已启动 PID=$($proc.Id)"
}

function Wait-BackendHealthy {
    param([Parameter(Mandatory = $true)][hashtable]$Cfg, [int]$TimeoutSec = 120)
    $port = $Cfg['BACKEND_PORT']
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    Write-Step "等待后端 http://127.0.0.1:$port/auth/user-types"
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/auth/user-types" -UseBasicParsing -TimeoutSec 5
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { Write-Ok '后端就绪'; return }
        } catch { Start-Sleep -Seconds 3 }
    }
    throw '后端超时，查看 logs\backend.stderr.log'
}

function Wait-ProxyHealthy {
    param([Parameter(Mandatory = $true)][hashtable]$Cfg, [int]$TimeoutSec = 60)
    $port = $Cfg['PROXY_PORT']
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    Write-Step "等待反代 http://127.0.0.1:$port/api/auth/user-types"
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/auth/user-types" -UseBasicParsing -TimeoutSec 5
            if ($resp.StatusCode -eq 200 -and $resp.Headers['Content-Type'] -like '*json*') { Write-Ok '反代就绪'; return }
        } catch { Start-Sleep -Seconds 2 }
    }
    throw '反代超时，检查 docker-compose.yml 中 caddyfile 配置'
}
