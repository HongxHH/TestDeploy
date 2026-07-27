# landcheck 部署包（TestDeploy）

访问地址：**http://localhost:8090/**


## 首次部署

### 1. 准备

1. 将整个 **TestDeploy** 复制到目标机器（如 `D:\landcheck\TestDeploy`）
2. 从 A 机**完整拷贝 Mongo 数据目录**到 B 机（拷贝前停止 Mongo）
3. 安装 **Docker Desktop**（勾选登录时启动）、**JDK 21**、**Node.js 18+**、**Git**；有 GPU 则安装 NVIDIA 驱动
4. 复制配置：`copy deploy.env.example deploy.env`，按 B 机实际情况修改（见下节）

缺少 Conda 时，PDF 预处理不可用；安装 Miniconda 后执行 `scripts\setup-conda.ps1`。

### 2. 一键部署

```powershell
cd D:\landcheck\TestDeploy
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

首次会：创建 Conda SR（如有 conda）→ 启动 Docker → 等待 OCR → 从代码仓库构建 → 启动后端。

---

## 配置说明（deploy.env）

从 `deploy.env.example` 复制，**勿提交 Git**。B 机应单独新建，不要直接拷贝 A 机的 `deploy.env`。

| 变量 | 说明 |
|------|------|
| `MONGO_DATA_DIR` | **必改**。Mongo 数据目录（A 机拷贝路径） |
| `SPRING_PROFILE` | 生产用 `prod`（关闭 Swagger） |
| `LANDCHECK_LLM_API_KEY` | **必改**。火山方舟 API Key（完整 UUID） |
| `LANDCHECK_MONGODB_URI` | Mongo 连接串，须与拷贝数据中的用户/密码一致 |
| `LANDCHECK_REDIS_PASSWORD` | 须与 `docker-compose.yml` 中 Redis 密码一致（默认 `123`） |
| `BACKEND_REPO_URL` / `FRONTEND_REPO_URL` | 代码仓库地址 |
| `GIT_BRANCH` | 拉取分支（默认 `main`） |
| `LANDCHECK_LOG_DIR` | 日志目录，建议改为 B 机绝对路径 |

默认仓库：

- 后端：`https://gitee.com/wqhshuaige/land-backend.git`
- 前端：`https://gitee.com/wqhshuaige/land-frontend.git`

**注意：** 修改 `deploy.env` 后须执行 `scripts\start-all.ps1` 重启后端，环境变量才会生效。

---

## 日常运维

### 命令速查

| 做什么 | 命令 |
|--------|------|
| 检查是否有新版本 | `scripts\check-updates.ps1` |
| **应用远程新代码** | `scripts\deploy.ps1` |
| 强制重新构建（无视版本检测） | `scripts\deploy.ps1 -Force` |
| 只更新后端 / 前端 | `scripts\deploy.ps1 -BackendOnly` / `-FrontendOnly` |
| 重启全部服务 | `scripts\start-all.ps1` |
| 快速重启（不等 OCR） | `scripts\start-all.ps1 -SkipOcrWait` |
| 查看运行状态与版本 | `scripts\status.ps1` |
| 停止后端 | `scripts\stop-all.ps1` |
| 停止后端 + Docker | `scripts\stop-all.ps1 -IncludeDocker` |
| 检查配置与容器 | `scripts\check-env.ps1` |

### 仓库有新代码时怎么更新

**首次部署用 `setup.ps1`，之后更新一律用 `deploy.ps1`，不必再跑 setup。**

```powershell
cd D:\landcheck\TestDeploy

# 可选：先看远程是否有新 commit
powershell -ExecutionPolicy Bypass -File scripts\check-updates.ps1

# 拉取 → 构建 → 替换 deploy/ → 重启
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
```

流程说明：

1. 对比远程 commit 与 `deploy/meta/*.deployed` 中记录的版本
2. 无更新则跳过；有更新则 `git clone` → Maven/npm 构建 → 更新 `deploy/` → 重启服务
3. 前提：**代码已 push 到 Gitee**（`BACKEND_REPO_URL` / `FRONTEND_REPO_URL`），且 B 机能访问该地址

仅改了 `deploy.env`（如 API Key）时，不需要 deploy，执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1 -SkipOcrWait
```

### 开发机同步代码到 Gitee

B 机只从 Gitee 拉代码。开发机每次改完并 push 到 GitHub 后，**同时 push 到 Gitee**：

```powershell
# 后端
cd E:\dev\Code\Java\landcheck\backend
git push origin main
git push gitee main

# 前端
cd E:\dev\Code\Java\landcheck\frontend
git push origin main
git push gitee main
```

若尚未添加 Gitee 远程：

```powershell
git remote add gitee https://gitee.com/wqhshuaige/land-backend.git   # 或 land-frontend.git
```

---

## B 机部署清单（无法访问 GitHub）

1. 复制整个 `TestDeploy` 到 B 机（如 `D:\landcheck\TestDeploy`）
2. 拷贝 Mongo 数据目录，修改 `deploy.env` 中的 `MONGO_DATA_DIR`、`LANDCHECK_LLM_API_KEY`、`LANDCHECK_LOG_DIR`
3. 确认仓库地址（public 库无需令牌）：

```env
BACKEND_REPO_URL=https://gitee.com/wqhshuaige/land-backend.git
FRONTEND_REPO_URL=https://gitee.com/wqhshuaige/land-frontend.git
```

4. 验证 B 机能访问 Gitee：

```powershell
git ls-remote https://gitee.com/wqhshuaige/land-backend.git HEAD
git ls-remote https://gitee.com/wqhshuaige/land-frontend.git HEAD
```

5. 首次部署：

```powershell
cd D:\landcheck\TestDeploy
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

6. 之后有更新时，先在开发机 push 到 Gitee，再在 B 机执行 `scripts\deploy.ps1`

---

## 开机自启（无人值守）

一次性配置：

1. Docker Desktop → Settings → **Start when you sign in**
2. 管理员 PowerShell 执行：`scripts\install-autostart.ps1`
3. 配置 Windows 自动登录，或约定重启后有人登录一次（计划任务在登录后触发）
4. 重启后查看 `logs\boot-start.log`

取消自启：`scripts\uninstall-autostart.ps1`

开机任务不等待 OCR 就绪（避免超时）；网站可先访问，OCR 约 5~10 分钟后可用。

---

## Conda 环境 SR（PDF 预处理）

脚本已打包进 JAR，运行时依赖宿主机 Conda 环境 **SR**：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-conda.ps1
```

依赖定义见 `conda/environment.yml`（pymupdf、opencv、numpy、scipy、pillow）。

---
