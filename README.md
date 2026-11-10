# LandCheck 测试机部署

在 Windows 上把整套系统跑起来。浏览器入口：**http://localhost:8090**。

本仓库没有业务代码。`deploy.ps1` 按 `deploy.env` 克隆前后端、构建，再启动宿主机上的后端。

- 后端：[land-backend](https://github.com/HongxHH/land-backend)
- 前端：[land-frontend](https://github.com/HongxHH/land-frontend)

## 这台机器上有什么

| 进程 | 位置 | 端口 |
| --- | --- | --- |
| Caddy | Docker | **8090**。静态前端；`/api` 转到宿主机 8082 |
| 后端 | 宿主机 JDK 21 | 8082 |
| MongoDB 8，副本集 `rs0` | Docker | 27017 |
| Redis | Docker | 6379，密码默认 `123` |
| RocketMQ NameServer + Broker | Docker | 9876 |
| PaddleOCR-VL | Docker，需要 NVIDIA GPU | 8080，`/layout-parsing` |
| PDF 预处理 | 宿主机 Conda 环境 `SR` | 无端口，由后端拉起 |

后端不在容器里。缺 Conda 时 PDF 预处理不可用，其余服务仍可起。

## 首次部署

1. 把本仓库拷到目标机器，例如 `D:\landcheck\TestDeploy`。
2. 停掉源机器的 Mongo，把数据目录完整拷过来。
3. 安装 Docker Desktop（勾选登录时启动）、JDK 21、Node.js 18+、Git。有 GPU 再装 NVIDIA 驱动。
4. `copy deploy.env.example deploy.env`，至少改 `MONGO_DATA_DIR` 和 `LANDCHECK_LLM_API_KEY`。不要直接拷源机器的 `deploy.env`。

```powershell
cd D:\landcheck\TestDeploy
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

`setup.ps1` 会创建 Conda `SR`（本机有 conda 时）、启动 Docker、等 OCR 健康、构建前后端、启动后端。没有 conda 时跳过 `SR`，之后可单独跑 `scripts\setup-conda.ps1`。

## 配置（deploy.env）

从 `deploy.env.example` 复制，不要提交。

| 变量 | 说明 |
| --- | --- |
| `MONGO_DATA_DIR` | 必改。Mongo 数据目录 |
| `LANDCHECK_LLM_API_KEY` | 必改。火山方舟 API Key |
| `LANDCHECK_MONGODB_URI` | 须与数据目录里的用户密码一致，且带 `replicaSet=rs0` |
| `LANDCHECK_REDIS_PASSWORD` | 与 compose 里 Redis 密码一致，默认 `123` |
| `SPRING_PROFILE` | 测试机用 `prod`，Swagger 关闭 |
| `BACKEND_REPO_URL` / `FRONTEND_REPO_URL` | 构建时 `git clone` 的地址 |
| `GIT_BRANCH` | 默认 `main` |
| `BACKEND_PORT` / `PROXY_PORT` | 默认 8082 / 8090 |
| `LANDCHECK_LOG_DIR` | 日志目录，改成这台机器的绝对路径 |

示例仓库：

- `https://github.com/HongxHH/land-backend.git`
- `https://github.com/HongxHH/land-frontend.git`

本机已有的 `deploy.env` 不会随仓库更新。仓库地址以该文件为准，改完后要重新构建。

改端口、密钥、Mongo、日志目录后，执行 `scripts\start-all.ps1` 重启后端。只改仓库地址或分支时，用下面的重新构建。

## 日常运维

同一时间只允许一个运维任务。重复双击会提示已有任务在进行。窗口结束前会暂停，方便看结果。

| 做什么 | 双击 |
| --- | --- |
| 停服务、拉代码、构建前后端、再启动 | `重新构建.bat` |
| 停后端、等 OCR、再启动 | `重新启动.bat` |
| 登录后延迟 2 分钟自启 | `设置开机自启.bat` |
| 取消自启 | `取消开机自启.bat` |

| 做什么 | 命令 |
| --- | --- |
| 强制重建并重启 | `scripts\deploy.ps1` |
| 重启（等 OCR） | `scripts\start-all.ps1` |
| 状态与版本 | `scripts\status.ps1` |
| 停后端 | `scripts\stop-all.ps1` |
| 停后端和 Docker | `scripts\stop-all.ps1 -IncludeDocker` |
| 检查配置与容器 | `scripts\check-env.ps1` |

首次用 `setup.ps1`。之后更新代码用 `deploy.ps1` 或 `重新构建.bat`。每次都会重新 `git clone` 前后端并构建，不跳过、不单更新一端。目标机器要能访问 `deploy.env` 里的仓库地址。

## 开机自启

双击 `设置开机自启.bat`（会要管理员权限）。登录后固定等 2 分钟，留给 Docker Desktop。

还需要：

1. Docker Desktop → Settings → Start when you sign in
2. Windows 自动登录，或重启后有人登录一次（计划任务在登录后触发）
3. 重启后看 `logs\boot-start.log`

取消：`取消开机自启.bat`。

## Conda 环境 SR

PDF 预处理脚本打在后端 JAR 里，运行时调用宿主机环境 **SR**。依赖在 `conda/environment.yml`（Python 3.10、PyMuPDF、OpenCV、NumPy、SciPy、Pillow）。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-conda.ps1
```
