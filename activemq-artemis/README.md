# 本地 Artemis（docker compose）

## etc-override 是什么？

官方镜像 `apache/activemq-artemis` 第一次启动会在容器里执行 `artemis create`，生成实例目录 `/var/lib/artemis-instance`（含 `etc/broker.xml`、`data/` 等）。

若把自定义配置放在宿主机的 **`etc-override/`** 并挂载到容器的 **`/var/lib/artemis-instance/etc-override`**，则 **仅在首次 create 时** 会把这些文件 **复制进 `etc/`**，之后 Broker 一直用这份配置启动。

因此：

- 适合把「开发用 broker.xml」版本化进 Git（本目录 `etc-override/broker.xml`）。
- **改完 broker.xml 后**，若已有旧的 `artemis-instance/`，需要删掉该目录再 `docker compose up`，否则会沿用旧 `etc/`。

## 启动（统一栈）

在 **company-docker** 目录：

```bash
cd company-docker
docker compose up -d artemis
# 或一次启动全部服务
docker compose up -d
```

控制台：http://127.0.0.1:8161 ，`admin` / `Artemis@2026`

本地数据目录：`./artemis-instance`（compose 中挂载为 `./activemq-artemis/artemis-instance`）。

## 修改 broker 配置后重建

```bash
cd company-docker
docker compose stop artemis
rm -rf ./activemq-artemis/artemis-instance
docker compose up -d artemis
```

## 权限说明（auth 报 CREATE_DURABLE_QUEUE）

官方镜像 `artemis-roles.properties` 默认是 **`amq = admin`**（用户 `admin` 属于角色 **`amq`**，不是 `admin`）。
若 `broker.xml` 里只写 `roles="admin"`，会报 `User: admin does not have permission='CREATE_DURABLE_QUEUE'`。

本目录 `etc-override` 已同时配置 `roles="amq,admin"` 与 `artemis-roles.properties`。

## 阿里云 / Linux：`The path '.' is not writable`

日志类似：

```text
The path '.' is not writable.
Usage: artemis help [<args>...]
```

**原因**：`artemis-instance/` 在 `.gitignore` 中，不会随仓库上传到服务器。首次 `docker compose up` 时 Docker 在宿主机创建空目录，属主多为 **root**；而官方镜像以非 root 用户（`2.42.0-alpine` 为 **UID 1001**）运行，无法在挂载点执行 `artemis create`，健康检查一直失败。

**修复**（在 `company-docker` 目录）：

```bash
docker compose -f docker-compose-amd64.yml stop artemis

# 若从未成功启动过，直接清空；若已有数据请自行备份
rm -rf ./activemq-artemis/artemis-instance
mkdir -p ./activemq-artemis/artemis-instance

# 须与镜像内 artemis 用户一致（2.42.0-alpine 为 1001；换版本请先执行下方 id 命令确认）
sudo chown -R 1001:1001 ./activemq-artemis/artemis-instance

docker compose -f docker-compose-amd64.yml up -d artemis
docker compose -f docker-compose-amd64.yml logs -f artemis
```

看到 `Artemis Message Broker ... started` 且 `docker compose ps` 中 artemis 为 `healthy` 即正常。

**勿**从 Mac 拷贝本机 `artemis-instance/` 到 Linux 服务器（属主/路径易不一致）。服务器上应只带 `etc-override/`，由容器首次启动生成实例。

确认 UID（换镜像版本时建议执行；须覆盖 entrypoint，否则 entrypoint 会跑 `artemis create` 而不是 `id`）：

```bash
docker run --rm --entrypoint id apache/activemq-artemis:2.42.0-alpine artemis
# 示例输出：uid=1001(artemis) gid=1001(artemis) → chown 用 1001:1001
```

## 与业务对齐

- JMS：`tcp://127.0.0.1:61616`（容器内服务名 `artemis:61616`）
- 账号：`admin` / `Artemis@2026`（与 `company-auth`、`company-auth-channel` 默认一致）
