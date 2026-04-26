# ActiveMQ Artemis — 生产级 Docker Compose 部署方案

## 目录结构

```
artemis-docker/
├── docker-compose.yml          # 主编排文件
├── .env                        # 环境变量 (勿提交 Git)
├── .gitignore
└── config/
    ├── broker-primary.xml      # 主节点 Broker 配置
    ├── broker-backup.xml       # 备节点 Broker 配置
    ├── bootstrap.xml           # Web 控制台启动配置
    ├── nginx.conf              # Nginx 主配置
    ├── nginx-artemis.conf      # Artemis 反向代理 (含图标修复)
    ├── jolokia-access.xml      # JMX API 访问控制
    ├── login.config            # JAAS 认证配置
    ├── artemis-users.properties # 用户列表
    └── artemis-roles.properties # 角色映射
```

---

## 快速启动

```bash
# 1. 修改 .env 中的密码
vim .env

# 2. 启动服务
docker compose up -d

# 3. 查看状态
docker compose ps
docker compose logs -f artemis-primary
```

访问控制台: **http://localhost/console** (通过 Nginx)  
或直接访问: **http://localhost:8161/console** (跳过 Nginx)

---

## 控制台图标显示正常 — 原理说明

### 问题根因

Hawtio (Artemis Web Console) 使用 **PatternFly 字体图标**，通过相对路径加载字体文件：

```
/console/static/fonts/PatternFlyIcons-webfont.woff2
/console/static/fonts/fontawesome-webfont.woff2
```

常见失效场景：

| 场景 | 原因 |
|------|------|
| Nginx `proxy_pass` 改写路径 | 字体 URL 变为 `/fonts/...`，实际请求 404 |
| `proxy_redirect` 未关闭 | `Location` 头被改写，重定向到错误地址 |
| 缺少 CORS 头 | 浏览器跨域字体请求被拒绝 |
| 未配置字体 MIME 类型 | Content-Type 错误，浏览器拒绝加载 |

### 本方案解决措施

```nginx
# ✅ 关键: 不改写 /console 前缀，保持路径透传
location /console {
    proxy_pass http://artemis_primary;   # 注意: 末尾无斜杠
    proxy_redirect off;                  # 必须: 禁止改写 Location 头
}

# ✅ 字体文件单独处理，添加 CORS 头
location ~* \.(woff|woff2|ttf|eot|otf)$ {
    proxy_pass http://artemis_primary;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
}
```

---

## 生产环境清单

### 密码安全

```bash
# 方式一: Docker Secrets (Swarm 模式)
echo "strong_password" | docker secret create artemis_password -

# 方式二: 使用 Artemis 工具生成 hash 密码
docker run --rm apache/activemq-artemis:2.40.0-alpine \
  /opt/activemq-artemis/bin/artemis user reset \
  --user admin --password "NewPassword!" --role admin

# 方式三: 手动生成 bcrypt hash
# 在 artemis-users.properties 中使用 ENC() 包裹
```

### 启用 TLS (生产必须)

```bash
# 1. 准备证书
mkdir -p certs
# 将 fullchain.pem 和 privkey.pem 放入 certs/

# 2. 取消 docker-compose.yml 中证书挂载注释
# 3. 取消 nginx-artemis.conf 中 HTTPS server 块注释
# 4. 修改 HTTP server 块: return 301 https://...
```

### Broker 间 TLS (mTLS)

在 `broker-primary.xml` 的 acceptor 中添加:

```xml
<acceptor name="artemis">
  tcp://0.0.0.0:61616?sslEnabled=true;keyStorePath=/path/to/keystore.jks;keyStorePassword=secret
</acceptor>
```

### 资源限制 (生产建议)

```yaml
# 在 docker-compose.yml service 中添加:
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 4G
    reservations:
      cpus: '2'
      memory: 2G
```

---

## HA 故障切换

### Replication 模式工作原理

```
┌─────────────────┐     数据同步     ┌─────────────────┐
│  Primary (Live) │ ─────────────── │  Backup (Passive)│
│  172.28.0.10    │                 │  172.28.0.11     │
└─────────────────┘                 └─────────────────┘
         │                                    │
         └──── 心跳检测 (5s) ────────────────┘
                    
主节点宕机 → 备节点检测到心跳超时 → 备节点升为 Primary
客户端使用 failover URL 自动重连:
  failover:(tcp://primary:61616,tcp://backup:61616)?retryInterval=1000
```

### 测试故障切换

```bash
# 停止主节点
docker compose stop artemis-primary

# 观察备节点日志 (应出现 "Primary is not available, starting backup server")
docker compose logs -f artemis-backup

# 恢复主节点 (backup 自动回退)
docker compose start artemis-primary
```

---

## 监控集成

### Prometheus + Grafana

Artemis 通过 Jolokia 暴露 JMX 指标，使用 jmx_exporter 转换为 Prometheus 格式：

```bash
# 在 docker-compose.yml 中添加 jmx_exporter sidecar
# 或使用 artemis-prometheus-metrics-plugin
```

### 常用 Jolokia API

```bash
# 查询 Broker 状态
curl -u admin:password http://localhost:8161/console/jolokia/read/org.apache.activemq.artemis:broker=\!\"artemis-primary\!\"/Started

# 查询队列深度
curl -u admin:password "http://localhost:8161/console/jolokia/read/org.apache.activemq.artemis:broker=!%22artemis-primary!%22,component=addresses,address=!%22MyQueue!%22,subcomponent=queues,routing-type=!%22anycast!%22,queue=!%22MyQueue!%22/MessageCount"
```

---

## 常见问题

**Q: Console 可以登录但图标显示为方块/乱码**  
A: 检查浏览器 Network 面板，过滤 `.woff2` 请求，确认字体文件返回 200 且 `Content-Type: font/woff2`。若 404，检查 Nginx `proxy_pass` 路径是否与 `bootstrap.xml` 的 `url` 属性一致。

**Q: 直连 8161 端口图标正常，但通过 Nginx 异常**  
A: 在 `nginx-artemis.conf` 中确认:  
1. `proxy_redirect off` 已启用  
2. 字体文件 `location ~* \.woff` 块存在  
3. `add_header Access-Control-Allow-Origin "*"` 已添加

**Q: 备节点无法连接主节点**  
A: 确认两个容器在同一 Docker 网络 (`artemis-net`)，且 `broker-backup.xml` 中 `primary-connector` 使用容器名 `artemis-primary` 而非 IP。

**Q: 大量消息时内存溢出**  
A: 检查 `global-max-size` 设置，确认 `address-full-policy` 为 `PAGE`（而非 `BLOCK` 或 `DROP`）。
