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

## 与业务对齐

- JMS：`tcp://127.0.0.1:61616`（容器内服务名 `artemis:61616`）
- 账号：`admin` / `Artemis@2026`（与 `company-auth`、`company-auth-channel` 默认一致）
