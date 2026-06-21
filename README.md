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
| `auth-channel/logs/` | auth-channel 滚动日志（`/var/log/auth-channel`，主文件 `auth-channel.log`） |
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

`auth` / `auth-channel` / `manage` 默认 `SPRING_PROFILES_ACTIVE=prod`，业务日志同时写 stdout 与 `./auth/logs` 等目录（格式一致）；`docker compose logs` 与文件内容对齐。

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

# 管理后台改路由/渠道/卡 BIN 后，在服务器上立即刷新 auth 路由缓存（POST /tools/cache/refresh）
./scripts/refresh-auth-route-cache.sh
# 拆分部署时指定 auth 地址：AUTH_API_BASE=http://192.168.0.125:8080 ./scripts/refresh-auth-route-cache.sh

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

1. 将 `company-docker` 目录（含 `docker-compose-amd64.yml`、`.env`、`init-db`、`activemq-artemis/etc-override` 等）与 tar 包传到服务器  
   **不要**上传本机 `activemq-artemis/artemis-instance/`（已在 gitignore，且 Mac 属主与 Linux 不一致易触发 Artemis 启动失败）。
2. 加载自研镜像并启动：

```bash
cd company-docker
docker load -i dist/company-images-amd64-latest.tar
cp -n .env.example .env   # 生产务必修改密码

# Artemis 数据目录须对容器内 artemis 用户可写（2.42.0-alpine 为 1001:1001，见 activemq-artemis/README.md）
mkdir -p ./activemq-artemis/artemis-instance
sudo chown -R 1001:1001 ./activemq-artemis/artemis-instance

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

### 跨 ECS / 拆分部署：网络连通性

多台 ECS 拆分部署时（例如 DB/Redis/auth 在 `192.168.0.125`，manage/admin-dashboard 在 `192.168.0.126`），应用日志里的 Redis/DB 超时，**优先按网络层排查**，不要先怀疑业务配置或 WAF。

#### 典型症状与含义

| 日志/现象 | 常见含义 |
|-----------|----------|
| `Connect timed out` / `connection timed out after 10000 ms` | TCP 包被丢弃或不可达（安全组、路由、对端未监听） |
| `Connection refused` | 端口可达，但进程未监听或立即拒绝 |
| `nc` / `/dev/tcp` **一直卡住** | 同 timeout，多为防火墙/安全组丢包 |
| `ping` 对端内网 IP **不通** | 两台实例之间 L3 就不通，不仅是某个端口 |
| 本机 `ping` / `nc` 自己 IP **成功** | 只说明本机服务正常，**不能**证明别的机器能连过来 |

#### 先分清：在哪台机器上测

| 测试命令执行位置 | 能说明什么 |
|------------------|------------|
| **DB 机**上 `nc 192.168.0.125:6379` | 仅本机自环，路由为 `dev lo`，**无效** |
| **调用方机器**（manage 所在 ECS）上测 | 才是真实跨机连通性 |

#### 推荐排查顺序（调用方 ECS 上执行）

将 `<对端IP>` 换成实际内网地址（如 `192.168.0.125`）。

**1. 看本机 IP 与路由**

```bash
hostname -I
ip route get <对端IP>
```

期望：`src` 为本机内网 IP，经 `eth0` 转发，而不是 `dev lo`。

**2. 宿主机连通性（不要先进容器）**

```bash
ping -c 3 <对端IP>

timeout 5 bash -c 'echo > /dev/tcp/<对端IP>/6379' && echo redis_ok || echo redis_fail
timeout 5 bash -c 'echo > /dev/tcp/<对端IP>/5432' && echo pg_ok || echo pg_fail
```

| 结果 | 下一步 |
|------|--------|
| `ping` 不通 | 查阿里云 **安全组 / 网络 ACL / 是否同一 VPC**（见下文） |
| `ping` 通、TCP fail | 多为 **端口级** 安全组未放行，或对端未监听该端口 |
| 宿主机 ok、容器 fail | 再查 Docker 网络（少见）；先确认容器 env 是否指向正确 IP |

**3. 对端确认服务已监听**

在 **DB/中间件 ECS** 上：

```bash
ss -lntp | grep -E '6379|5432'
```

期望：`0.0.0.0:6379` / `0.0.0.0:5432`（或 docker-proxy 绑定 `0.0.0.0`），不要只有 `127.0.0.1`。

**4. 抓包定因（可选但最准）**

对端 ECS 上：

```bash
tcpdump -i eth0 host <调用方内网IP> and \( port 6379 or port 5432 \) -n
```

调用方再执行一次 `/dev/tcp` 或 `nc`。  

| 抓包结果 | 结论 |
|----------|------|
| 完全没有 SYN | 安全组/ACL/路由在到达对端前拦了 |
| 有 SYN、无 SYN-ACK | 对端本机规则或监听异常 |
| 有 SYN-ACK | 网络已通，再查密码、`pg_hba`、Redis `requirepass` |

**5. 核对应用环境变量**

```bash
docker exec company-manage env | grep -E 'MANAGE_DB|MANAGE_REDIS'
docker exec company-admin-dashboard env | grep -E 'DATABASE_URL|_API_BASE'
```

#### 同一 VPC ≠ 自动互通（阿里云安全组）

- **同一 VPC** 只保证路由在同一内网，**不保证**实例互访所有端口。
- **同一安全组** 且默认组内互信时，通常 ICMP/TCP 全通。
- **不同安全组** 时，必须在 **对端安全组入方向** 放行调用方内网 IP（如 `192.168.0.126/32`）的所需端口。

控制台检查两台 ECS：**VPC ID**、**安全组 ID** 是否一致；若曾「隔离安全组」，会导致 `ping` 与 Redis/Postgres 同时超时。

对端（DB 机）入方向示例：

| 协议 | 端口 | 授权对象 |
|------|------|----------|
| ICMP（可选，便于 ping 排查） | 全部 | `192.168.0.126/32` |
| TCP | 6379 | `192.168.0.126/32` |
| TCP | 5432 | `192.168.0.126/32` |

本机 `firewall-cmd` / `iptables INPUT ACCEPT` **看不到** 安全组规则；`ping` 不通时优先看控制台。

#### 拆分部署时的环境变量写法

**manage 与 DB 不在同一套 compose** 时，须用 **对端内网 IP**，不能用容器名 `redis` / `postgres`：

```bash
MANAGE_REDIS_HOST=192.168.0.125
MANAGE_DB_URL=jdbc:postgresql://192.168.0.125:5432/company_auth?currentSchema=manage
```

**admin-dashboard** 的 `DATABASE_URL` 格式为 `postgresql://用户名:密码@主机:端口/库名`，IP 写在 **`@` 后面**：

```bash
# 正确
DATABASE_URL=postgresql://postgres:密码@192.168.0.125:5432/company_auth

# 错误（IP 被当成用户名，主机仍是 postgres）
DATABASE_URL=postgresql://192.168.0.125:密码@postgres:5432/company_auth
```

**manage 与 postgres/redis 在同一套 compose** 时，应使用服务名：

```bash
MANAGE_REDIS_HOST=redis
MANAGE_DB_URL=jdbc:postgresql://postgres:5432/company_auth?currentSchema=manage
```

#### WAF / 雷池 与 Redis、DB 超时无关

反向代理（如雷池 SafeLine、Nginx WAF）只处理 **入站 HTTP**（如 admin-dashboard:3000），**不会**拦截 manage 容器/宿主机 **出站** 访问 `对端IP:6379` / `:5432`。

若仅在前端挂了 WAF 后出现 manage 连不上 Redis，多为 **同时期改了安全组或拆分部署刚生效**，时间重合而已。

在调用方 ECS 上确认 Docker 未误拦出站：

```bash
iptables -L DOCKER-USER -n -v --line-numbers
iptables-save | grep -E 'DROP|REJECT'
```

`DOCKER-USER` 仅 `RETURN`、且无针对内网 IP 的 `DROP` 时，可排除本机 iptables；宿主机 `ping`/`TCP` 失败仍应查 **安全组**。

#### 容器镜像运行用户与挂载目录权限

跨机网络通之后，若仍有 **日志写入 Permission denied** 或 Artemis `The path '.' is not writable`，需让挂载目录属主与容器内用户一致。

查 UID（须 `--entrypoint`，否则 entrypoint 会跑应用而非 `id`）：

```bash
# 自研服务（镜像内用户 app）
docker run --rm --entrypoint id company-auth:amd64 app
docker run --rm --entrypoint id company-manage:amd64 app

# Artemis 官方镜像（2.42.0-alpine 一般为 1001，以实际输出为准）
docker run --rm --entrypoint id apache/activemq-artemis:2.42.0-alpine artemis
```

运行中容器：

```bash
docker exec company-manage id
```

对挂载目录 `chown`（示例 UID/GID 以 `id` 输出为准）：

```bash
sudo chown -R 100:101 ./manage/logs
sudo chown -R 1001:1001 ./activemq-artemis/artemis-instance
```

详见 [activemq-artemis/README.md](./activemq-artemis/README.md)。

#### 网络恢复后重启业务容器

```bash
docker compose -f docker-compose-amd64.yml restart manage
docker compose -f docker-compose-amd64.yml logs -f manage --tail 50
```

---

### Artemis 反复 unhealthy：`The path '.' is not writable`

见 [activemq-artemis/README.md](./activemq-artemis/README.md#阿里云--linux-the-path--is-not-writable)。  
简要：`mkdir` + `chown -R 1001:1001 ./activemq-artemis/artemis-instance`（2.42.0-alpine）后重启 artemis。

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

若仍见 Logback 的 `Missing watchable`，请重建镜像（`logback-spring.xml` 已 `scan=false`）。各环境日志格式统一，由 `application-logging.yml` 按 profile 区分级别。

### 管理台接口 500 / `127.0.0.1` / `fetch failed`

- **`DATABASE_URL` / `MANAGE_API_BASE` 等连到本机**：多为未重建 dashboard 或 env 未注入；确认 `docker exec company-admin-dashboard env | grep _API_BASE`。
- **生成插件包 `Cannot run program "bash"`**：需重建 `company-auth` 镜像（Dockerfile 含 `apk add bash zip file`），并保证 `tools/channel-plugin` 挂载可写（生成 `workspaces/`、`dist/`）。

## 历史说明

原先分散的 `postgres/docker-compose.yml`、`redis/docker-compose.yml`、`activemq-artemis/docker-compose.yml` 已合并为本文件；请仅在本目录使用统一编排。
