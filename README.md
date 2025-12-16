# Sing-Box Auto-Deploy Docker Container

一键自动部署四种协议的 sing-box 容器，支持完全自动化配置。

## 特性

- ✅ **VLESS-Vision-uTLS-REALITY** - 基于 Reality 的 VLESS 协议
- ✅ **AnyTLS** - 通用 TLS 隧道
- ✅ **Hysteria2** - 基于 QUIC 的高速协议
- ✅ **TUIC V5** - 基于 QUIC 的低延迟协议

### 自动化功能

- 🔄 自动检测公网 IP
- 🔐 自动生成 UUID 和 Reality 密钥对
- 📜 自动通过 sslip.io + Let's Encrypt 获取 SSL 证书
- 🎲 支持随机端口分配
- 🔗 自动生成分享链接

## 快速开始

### 方式一：使用部署脚本（推荐）

```bash
# 克隆或进入目录
cd /path/to/ez/docker

# 赋予执行权限
chmod +x deploy.sh

# 一键部署（全部默认配置，端口随机）
./deploy.sh up

# 查看日志和分享链接
./deploy.sh logs -f
```

### 方式二：使用 Docker Compose

```bash
cd /path/to/ez/docker

# 直接启动
docker-compose up -d

# 查看日志
docker-compose logs -f
```

### 方式三：直接使用 Docker

```bash
cd /path/to/ez/docker

# 构建镜像
docker build -t sing-box-auto .

# 运行容器
docker run -d \
  --name sing-box-auto \
  --network host \
  --cap-add NET_ADMIN \
  -v $(pwd)/data/tls:/etc/sing-box/tls \
  -v $(pwd)/data/config:/etc/sing-box/conf \
  sing-box-auto
```

## 配置选项

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `ENABLE_REALITY` | `1` | 启用 VLESS-Reality (1=启用, 0=禁用) |
| `ENABLE_ANYTLS` | `1` | 启用 AnyTLS |
| `ENABLE_HYSTERIA2` | `1` | 启用 Hysteria2 |
| `ENABLE_TUIC` | `1` | 启用 TUIC V5 |
| `REALITY_PORTS` | 随机 | Reality 端口，支持逗号分隔多端口 |
| `ANYTLS_PORTS` | 随机 | AnyTLS 端口，支持逗号分隔多端口 |
| `HYSTERIA2_PORTS` | 随机 | Hysteria2 端口，支持逗号分隔多端口 |
| `TUIC_PORTS` | 随机 | TUIC 端口，支持逗号分隔多端口 |
| `UUID` | 自动生成 | 用户 UUID |
| `REALITY_SERVER_NAME` | 随机选择 | Reality 伪装域名 |
| `REALITY_SERVER_PORT` | `443` | Reality 伪装端口 |
| `CUSTOM_DOMAIN` | 空 (使用 sslip.io) | 自定义 TLS 域名 |
| `HYSTERIA2_UP_MBPS` | `100` | Hysteria2 上传带宽 (Mbps) |
| `HYSTERIA2_DOWN_MBPS` | `100` | Hysteria2 下载带宽 (Mbps) |
| `TUIC_CONGESTION` | `bbr` | TUIC 拥塞控制算法 (bbr/cubic/new_reno) |
| `NAME_PREFIX` | 空 | 分享链接里的节点名称前缀；支持写 `us1` 或 `us1-`，会生成 `us1-协议名称-端口`（如 `us1-Reality-443`） |

### Reality 可用伪装域名

容器会自动从以下域名列表中随机选择：

- Apple: `gateway.icloud.com`, `itunes.apple.com`, `swdist.apple.com`
- Mozilla: `download-installer.cdn.mozilla.net`, `addons.mozilla.org`
- CDN: `s0.awsstatic.com`, `cdn-dynmedia-1.microsoft.com`
- 技术网站: `www.python.org`, `vuejs.org`, `react.dev`, `redis.io`
- 其他: `www.cisco.com`, `www.samsung.com`, `academy.nvidia.com`

## 使用示例

### 示例 1：完全自动配置

```bash
./deploy.sh up
```

所有配置自动生成，端口随机分配。

### 示例 2：指定 UUID

```bash
./deploy.sh up --uuid "your-custom-uuid-here"
```

### 示例 3：指定端口

```bash
./deploy.sh up \
  --reality-port 443 \
  --anytls-port 8443 \
  --hy2-port 10000 \
  --tuic-port 10001
```

### 示例 4：多端口配置

```bash
./deploy.sh up \
  --reality-port "443,444,445" \
  --hy2-port "10000,10001,10002"
```

### 示例 5：只启用特定协议

```bash
# 只启用 Reality
./deploy.sh up --only-reality --reality-port 443

# 只启用 Hysteria2
./deploy.sh up --only-hy2 --hy2-port 443

# 禁用特定协议
./deploy.sh up --no-anytls --no-tuic
```

### 示例 6：使用自定义域名

```bash
# 使用自定义域名（需要将域名解析到服务器 IP）
./deploy.sh up --domain proxy.example.com
```

### 示例 7：使用 Docker Compose 自定义

编辑 `docker-compose.yaml`：

```yaml
services:
  sing-box:
    environment:
      - NAME_PREFIX=us1  # 可选：分享链接节点名 -> us1-Reality-443 / us1-AnyTLS-8443 ...
      - ENABLE_REALITY=1
      - ENABLE_ANYTLS=0
      - ENABLE_HYSTERIA2=1
      - ENABLE_TUIC=0
      - REALITY_PORTS=443,8443
      - HYSTERIA2_PORTS=10000
      - UUID=your-custom-uuid
      - REALITY_SERVER_NAME=www.microsoft.com
      - CUSTOM_DOMAIN=proxy.example.com  # 可选：自定义域名
```

然后运行：

```bash
docker-compose up -d
```

## 常用命令

```bash
# 启动
./deploy.sh up

# 停止
./deploy.sh down

# 重启
./deploy.sh restart

# 查看日志
./deploy.sh logs
./deploy.sh logs -f  # 实时跟踪

# 查看状态
./deploy.sh status

# 查看分享链接
./deploy.sh links

# 查看当前配置
./deploy.sh config

# 重新构建镜像
./deploy.sh build

# 清理所有数据
./deploy.sh clean
```

## 输出示例

启动后，日志中会显示：

```
==============================================
         DEPLOYMENT COMPLETE
==============================================

Server: 1.2.3.4
UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
TLS Domain: 1-2-3-4.sslip.io (sslip.io auto)

=== VLESS-Reality-Vision ===
Server: 1.2.3.4
Server Name (SNI): www.microsoft.com
Public Key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Short ID: xxxxxxxxxxxxxxxx
Ports: 12345

=== Hysteria2 ===
Server: 1.2.3.4
SNI: 1-2-3-4.sslip.io
Ports: 23456
Up/Down: 100/100 Mbps

==============================================
         SHARE LINKS
==============================================
vless://xxx@1.2.3.4:12345?...#Reality-12345
hysteria2://xxx@1.2.3.4:23456?...#Hysteria2-23456
...
==============================================
```

## 数据持久化

容器会自动创建以下目录存储数据：

```
./data/
├── tls/              # SSL 证书
├── config/           # 配置文件
└── letsencrypt/      # Let's Encrypt 数据
```

## 网络模式

默认使用 `host` 网络模式以获得最佳性能。如果需要使用 `bridge` 模式，请修改 `docker-compose.yaml`：

```yaml
services:
  sing-box:
    # 注释掉 host 模式
    # network_mode: host
    
    # 启用端口映射
    ports:
      - "443:443/tcp"
      - "443:443/udp"
      - "8443:8443/tcp"
      - "8443:8443/udp"
```

## 证书说明

- **VLESS-Reality**: 不需要真实证书，使用 Reality 协议
- **AnyTLS/Hysteria2/TUIC**: 自动通过 `IP.sslip.io` + Let's Encrypt 获取证书
- 如果设置了 `CUSTOM_DOMAIN`，则使用自定义域名获取证书
- 如果 Let's Encrypt 获取失败，会自动生成自签名证书

### 关于域名显示

- **Server**: 服务器的实际 IP 地址，客户端连接时使用此地址
- **SNI**: TLS 握手时使用的服务器名称指示，用于证书验证
- 默认情况下 SNI 使用 sslip.io 格式（如 `1-2-3-4.sslip.io`）
- 可通过 `CUSTOM_DOMAIN` 环境变量设置自定义域名

## 故障排除

### 端口被占用

```bash
# 检查端口占用
ss -tlnp | grep <port>

# 使用其他端口
./deploy.sh up --reality-port 8443
```

### 证书获取失败

1. 确保 80 端口可访问（Let's Encrypt 验证需要）
2. 检查防火墙设置
3. 容器会自动回退到自签名证书

### 查看详细日志

```bash
./deploy.sh logs -f
```

### 重置所有配置

```bash
./deploy.sh clean
./deploy.sh up
```

## 安全建议

1. 定期更换 UUID
2. 使用防火墙限制访问来源
3. 定期更新容器镜像
4. 监控异常流量

## License

MIT License