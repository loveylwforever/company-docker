# company-docker

在 **本目录** 一键构建并启动：Postgres、Redis、Artemis、`company-auth`、`company-auth-channel`、`company-manage`、`company-admin-dashboard`（admin-dashboard）。

> **说明**：接口文档子模块 `company-auth-docs` 仅部署在 Vercel，已写入父仓库 `.dockerignore`，不参与本栈镜像构建。

所有持久化与业务挂载均使用 `./` 相对路径（数据落在 `company-docker` 下，便于统一管理）。

## 目录结构

| 路径 | 说明 |
|------|------|
| `docker-compose.yml` | 本地开发编排（自研镜像标签 `:local`） |
| `docker-compose-amd64.yml` | 阿里云 amd64 发布编排（自研镜像标签 `:amd64`） |
| `build-push-amd64.sh` | Mac 交叉编译 amd64 并导出离线 tar |
| `dist/` | 离线镜像包输出目录（gitignore） |
| `images/` | `company-auth` / `company-auth-channel` / `company-manage` / `admin-dashboard` 镜像 Dockerfile |
| `init-db/` | Postgres 首次初始化脚本 |
| `postgres/postgres_data/` | Postgres 数据（本地挂载，已 gitignore） |
| `redis/redis-data/` | Redis 数据（本地挂载，已 gitignore） |
| `activemq-artemis/` | Artemis 实例与 `etc-override` |
| `auth/fail-insert/` | auth 落库失败本地 SQL |
| `auth/logs/` | auth 滚动日志（`prod` profile，`/var/log/auth`） |
| `auth-channel/plugins/` | 渠道插件 JAR（发布升级写入） |
| `auth-channel/logs/` | auth-channel 滚动日志（`/var/log/company-auth-channel`） |
| `manage/logs/` | manage 滚动日志（`/var/log/company-manage`） |

源码与 SQL 通过 `../` 相对路径引用；Java 与 admin-dashboard 镜像构建上下文均为上级 **company-parent** 根目录，Dockerfile 统一在 `company-docker/images/` 下。

## 前置

- Docker Compose v2
- 父仓库已克隆且包含子模块：`company-auth`、`company-sql`、`tools/channel-plugin` 等

```bash
# 在 company-parent 根目录
git submodule update --init --recursive company-docker company-auth company-sql
```

## 启动

```bash
cd company-docker
cp -n .env.example .env   # 可选
docker compose up -d --build
```

首次会 Maven 打包 Java 服务（上下文为 `..`），耗时数分钟。构建使用 `company-docker/maven/settings.xml`（阿里云 Central 镜像）。

`auth` / `auth-channel` / `manage` 默认 `SPRING_PROFILES_ACTIVE=prod`，业务日志写入对应 `./auth/logs`、`./auth-channel/logs`、`./manage/logs`；READY Banner 统一写 stdout，`docker compose logs` 可见。

## 端口与账号（默认）

| 服务 | 端口 | 说明 |
|------|------|------|
| Postgres | 5432 | `postgres` / `postgres`，库 `company_auth` |
| Redis | 6379 | 密码 `123456` |
| Artemis 控制台 | 8161 | `admin` / `Artemis@2026` |
| Artemis Core | 61616 | JMS |
| company-auth | 8080 | HTTP API |
| company-auth-channel | 8090 | `GET /tools/channel/ping` |
| company-manage | 8088 | 管理端安全登录 API（Sa-Token + Redis） |
| admin-dashboard | 3000 | 管理台（Nuxt）；浏览器访问 http://127.0.0.1:3000 |

## 常用命令

```bash
cd company-docker

docker compose ps
docker compose logs -f auth auth-channel admin-dashboard
docker compose down

# 停止并删除本地数据目录内容（需自行 rm 或清空 ./postgres/postgres_data 等）
docker compose down
```

> 未使用 Docker 命名卷；数据均在 `./postgres/postgres_data`、`./redis/redis-data` 等目录。清空 DB 请删除对应目录后重新 `up`。

## 阿里云 Intel（amd64）离线发布

本地 Mac 开发用 `docker-compose.yml`，镜像标签 **`:local`**；发布到阿里云 x86 用 **`docker-compose-amd64.yml`**，标签 **`:amd64`**，两者互不覆盖。

### Mac 上构建并打包

```bash
cd company-docker
chmod +x build-push-amd64.sh   # 首次
./build-push-amd64.sh
```

产出：

- 镜像：`company-auth:amd64`、`company-auth-channel:amd64`、`company-manage:amd64`、`admin-dashboard:amd64`
- 离线包：`dist/company-images-amd64-<时间戳>.tar`（软链 `dist/company-images-amd64-latest.tar`）

可选环境变量：

```bash
# 构建内存不足时提高 admin-dashboard 构建堆
NODE_HEAP_MB=3072 ./build-push-amd64.sh

# 仅构建不打包
./build-push-amd64.sh --no-save
```

### 阿里云 ECS 部署

1. 将 `company-docker` 目录（含 `docker-compose-amd64.yml`、`.env`、`init-db` 等）与 tar 包传到服务器  
2. 加载自研镜像并启动：

```bash
cd company-docker
docker load -i dist/company-images-amd64-latest.tar
cp -n .env.example .env   # 生产务必修改密码
docker compose -f docker-compose-amd64.yml up -d
```

> **说明**：tar 仅含四个自研服务。Postgres / Redis / Artemis 首次 `up` 时从 Docker Hub 拉取 `linux/amd64` 官方镜像（需服务器能访问 Hub，或另行离线导入）。

### 标签对照

| 场景 | compose 文件 | 自研镜像标签 |
|------|----------------|--------------|
| 本机 Mac 验证 | `docker-compose.yml` | `:local` |
| 阿里云 x86 发布 | `docker-compose-amd64.yml` | `:amd64` |

## Artemis 配置变更

修改 `./activemq-artemis/etc-override/broker.xml` 后：

```bash
docker compose stop artemis
rm -rf ./activemq-artemis/artemis-instance
docker compose up -d artemis
```

## 管理台（admin-dashboard）

浏览器只访问 **http://127.0.0.1:3000**；Nitro 再按前缀转发（详见 [company-admin-dashboard/README.md](../company-admin-dashboard/README.md)）。

### 容器环境变量 → BFF 前缀

| 环境变量 | 容器内典型值 | 浏览器路径前缀 | 上游 |
|----------|--------------|----------------|------|
| `DATABASE_URL` | `postgresql://postgres:...@postgres:5432/company_auth` | `/api/db/*` | PostgreSQL |
| `AUTH_API_BASE` | `http://auth:8080` | `/api/auth/*` | company-auth |
| `CHANNEL_RELEASE_API_BASE` | `http://auth-channel:8090` | `/api/channel-release/*` | company-auth-channel |
| `MANAGE_API_BASE` | `http://manage:8088` | `/api/manage/*` | company-manage |
| `MANAGE_ENCRYPT_KEY` | 与 manage 一致 | （前端 public 配置） | — |

Nitro 服务端读取上游地址时**优先 `process.env`**，避免镜像构建期把 `127.0.0.1` 烘焙进 `runtimeConfig`。改 env 后请 `docker compose up -d --build admin-dashboard`。

### company-auth 与渠道插件

- `CHANNEL_PLUGIN_HOME=/opt/channel-plugin`（挂载 `../tools/channel-plugin`）
- 镜像内已安装 `bash`、`zip`、`file`（`generate.sh` 需要；Alpine JRE 默认无 bash）
- 管理台「生成插件包」：`POST /api/auth/tools/channel-plugin/generate` → auth `POST /tools/channel-plugin/generate`

渠道发布 JAR 落盘：`./auth-channel/plugins`（容器内 `/data/plugins`）。

### 产品自测（Self Verify）

管理台菜单 **在线开发 → 产品自测**（`/self-verify`）在页内选择商户编号与账号，`company-manage` 读取 `api_key` 后签名并转发 `company-auth`（真实交易）。

**前置**：在管理台创建正常商户/账号，配置 `api_key`、路由与应答码。`manage` 容器需 `AUTH_API_BASE=http://auth:8080`（compose 已配置）。

**冒烟**：选择商户/账号后，对 11 个 productType 点击「填充样例」→「发送」。

## 故障排查

### `company-auth` 反复重启（exit 1）

`prod` 日志默认不写控制台，请看挂载日志：

```bash
tail -50 auth/logs/auth-error.log
```

常见原因：**Redis 容器未加入 compose 网络**。此时 `redis` 会解析到本机代理的 fake-ip（如 `198.18.0.x`），Redisson 报 `RedisTimeoutException` / `Unable to connect to Redis server`。

检查：

```bash
docker inspect company-redis --format '{{json .NetworkSettings.Networks}}'
# 应包含 company-stack_company-net 及 IP，不能是 {}
```

修复：

```bash
docker compose up -d --force-recreate redis
docker compose restart auth
```

同网段连通性自测（应返回 `PONG`）：

```bash
docker run --rm --network company-docker_company-net redis:8.0-alpine \
  redis-cli -h redis -a "123456" ping
```

> 网络名以 `docker network ls` 为准（compose 项目名 + `_company-net`）。

若仍见 Logback 的 `CONSOLE not referenced` / `Missing watchable`，请重建 `company-auth` 镜像（`logback-spring.xml` 已关闭 scan 且 prod 不注册 CONSOLE appender）。

### 管理台接口 500 / `127.0.0.1` / `fetch failed`

- **`DATABASE_URL` / `MANAGE_API_BASE` 等连到本机**：多为未重建 dashboard 或 env 未注入；确认 `docker exec company-admin-dashboard env | grep _API_BASE`。
- **生成插件包 `Cannot run program "bash"`**：需重建 `company-auth` 镜像（Dockerfile 含 `apk add bash zip file`），并保证 `tools/channel-plugin` 挂载可写（生成 `workspaces/`、`dist/`）。

## 历史说明

原先分散的 `postgres/docker-compose.yml`、`redis/docker-compose.yml`、`activemq-artemis/docker-compose.yml` 已合并为本文件；请仅在本目录使用统一编排。
