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

### 一键操作（推荐，双击即可）

| 做什么 | 文件 |
|--------|------|
| **重新构建**（停服务 → 拉代码 → 构建前后端 → 启动） | `重新构建.bat` |
| **重新启动**（停后端 → 等 OCR → 启动） | `重新启动.bat` |
| **设置开机自启**（登录后固定延迟 **2 分钟**） | `设置开机自启.bat` |
| **取消开机自启** | `取消开机自启.bat` |

防呆说明：同一时间只允许一个运维任务（重建/重启/自启设置互斥）；重复双击会提示「另一项运维操作正在进行中」。窗口结束前会 `pause`，方便查看结果。

### 命令速查（PowerShell）

| 做什么 | 命令 |
|--------|------|
| **应用远程新代码（前后端强制重建）** | `scripts\deploy.ps1` |
| 重启全部服务（等待 OCR） | `scripts\start-all.ps1` |
| 查看运行状态与版本 | `scripts\status.ps1` |
| 停止后端 | `scripts\stop-all.ps1` |
| 停止后端 + Docker | `scripts\stop-all.ps1 -IncludeDocker` |
| 检查配置与容器 | `scripts\check-env.ps1` |

### 仓库有新代码时怎么更新

**首次部署用 `setup.ps1`，之后更新一律用 `deploy.ps1`（或双击 `重新构建.bat`），不必再跑 setup。**

```powershell
cd D:\landcheck\TestDeploy

# 拉取 → 构建前后端 → 替换 deploy/ → 重启（每次均强制重建）
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
```

流程说明：

1. 每次执行均 `git clone` 前后端 → Maven/npm 构建 → 更新 `deploy/` → 重启服务（不跳过、不单独更新一端）
2. 前提：**代码已 push 到 Gitee**（`BACKEND_REPO_URL` / `FRONTEND_REPO_URL`），且 B 机能访问该地址


```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1
```

## 开机自启（无人值守）

推荐双击 `设置开机自启.bat`（会请求管理员权限）。登录后固定延迟 **2 分钟** 再启动服务（给 Docker Desktop 留启动时间）。

一次性确认：

1. Docker Desktop → Settings → **Start when you sign in**
2. 配置 Windows 自动登录，或约定重启后有人登录一次（计划任务在登录后触发）
3. 重启后查看 `logs\boot-start.log`

取消自启：双击 `取消开机自启.bat`（或 `scripts\uninstall-autostart.ps1`）

---

## Conda 环境 SR（PDF 预处理）

脚本已打包进 JAR，运行时依赖宿主机 Conda 环境 **SR**：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-conda.ps1
```

依赖定义见 `conda/environment.yml`（pymupdf、opencv、numpy、scipy、pillow）。

---
