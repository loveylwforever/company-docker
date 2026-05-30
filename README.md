# company-docker

在 **本目录** 一键构建并启动：Postgres、Redis、Artemis、`company-auth`、`company-auth-channel`、`company-admin-dashboard`（admin-dashboard）。

所有持久化与业务挂载均使用 `./` 相对路径（数据落在 `company-docker` 下，便于统一管理）。

## 目录结构

| 路径 | 说明 |
|------|------|
| `docker-compose.yml` | 统一编排（在此目录执行 `docker compose`） |
| `images/` | `company-auth` / `company-auth-channel` / `admin-dashboard` 镜像 Dockerfile |
| `init-db/` | Postgres 首次初始化脚本 |
| `postgres/postgres_data/` | Postgres 数据（本地挂载，已 gitignore） |
| `redis/redis-data/` | Redis 数据（本地挂载，已 gitignore） |
| `activemq-artemis/` | Artemis 实例与 `etc-override` |
| `auth/fail-insert/` | auth 落库失败本地 SQL |
| `auth/logs/` | auth 滚动日志（`prod` profile，`/var/log/auth`） |
| `auth-channel/plugins/` | 渠道插件 JAR（发布升级写入） |
| `auth-channel/logs/` | auth-channel 滚动日志（`/var/log/company-auth-channel`） |

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

首次会 Maven 打包 Java 服务（上下文为 `..`），耗时数分钟。

`auth` / `auth-channel` 默认 `SPRING_PROFILES_ACTIVE=prod`，日志写入上述 `./auth/logs`、`./auth-channel/logs` 挂载目录（`prod` 仅写文件、不打控制台，可用 `tail -f auth/logs/auth.log` 查看）。

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
