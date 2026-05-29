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

容器内已通过环境变量对接后端：

- `AUTH_API_BASE` → `http://auth:8080`
- `CHANNEL_RELEASE_API_BASE` → `http://auth-channel:8090`
- `MANAGE_API_BASE` → `http://company-manage:8088`
- `DATABASE_URL` → Postgres 库 `company_auth`
- `MANAGE_ENCRYPT_KEY` → 与 `company-manage` 加密密钥保持一致

浏览器访问 **http://127.0.0.1:3000**。渠道发布升级的 JAR 落盘目录为 `./auth-channel/plugins`（容器内 `/data/plugins`）。

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
docker run --rm --network company-stack_company-net redis:8.0-alpine \
  redis-cli -h redis -a "123456" ping
```

控制台里 Logback 的 `CONSOLE not referenced`、`Missing watchable` 在 `prod` 下属正常，不是崩溃原因。

## 历史说明

原先分散的 `postgres/docker-compose.yml`、`redis/docker-compose.yml`、`activemq-artemis/docker-compose.yml` 已合并为本文件；请仅在本目录使用统一编排。
