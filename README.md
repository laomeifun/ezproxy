# EZProxy (Sing-Box Auto-Deploy)

基于 Docker 的 Sing-Box 自动部署工具，支持多种协议的一键配置与管理。

## ✨ 特性

- **多协议支持**：
  - ✅ **VLESS-Vision-uTLS-REALITY** (默认启用)
  - ✅ **Hysteria2** (默认启用)
  - ❌ AnyTLS (可选)
  - ❌ TUIC V5 (可选)
- **自动化配置**：
  - 自动生成 UUID 和密钥
  - 自动配置 SSL 证书 (自签名或 Let's Encrypt)
  - 自动输出客户端分享链接

## 🚀 快速开始

### 1. 环境要求

- Docker
- Docker Compose

### 2. 启动服务

下载本项目后，在项目根目录下运行：

```bash
# 启动服务
docker compose up -d

# 查看日志（包含分享链接）
docker compose logs -f
```

首次启动时，容器会自动生成配置并输出分享链接。请留意日志中的 `[INF] Share Link:` 部分。

### 3. 配置说明

你可以通过修改 `docker-compose.yaml` 中的环境变量来自定义配置：

```yaml
environment:
  # 协议开关 (1=启用, 0=禁用)
  - ENABLE_REALITY=1
  - ENABLE_ANYTLS=0
  - ENABLE_HYSTERIA2=1
  - ENABLE_TUIC=0
  
  # 端口配置 (留空则随机分配)
  - REALITY_PORTS=443
  - HYSTERIA2_PORTS=50000
  
  # 固定 UUID (可选，留空自动生成)
  - UUID=
  
  # 证书模式
  # selfsigned: 自签名证书 (推荐配合 Reality 使用)
  # letsencrypt: 自动申请真实证书 (需要 80 端口)
  - LE_MODE=selfsigned
```

## 📂 文件结构

- `data/conf`: 存放 Sing-Box 配置文件 (`config.json`) 和分享链接 (`share_links.txt`)
- `data/tls`: 存放证书文件

## ⚠️ 注意事项

- **网络模式**：本项目默认使用 `host` 网络模式，以便处理大量端口映射。
- **端口修改**：如果需要修改端口，请直接在 `docker-compose.yaml` 中修改对应的环境变量。
- **配置持久化**：`REUSE_CONFIG=1` 默认开启，重启容器后会保留之前的 UUID 和证书配置。如果需要重置，请删除 `data` 目录或将该变量设为 `0`。
- **端口跳跃**：Hysteria2 协议默认启用了端口跳跃功能。请确保你的防火墙（如 UFW、iptables 或云服务商的安全组）放行了相应的 UDP 端口范围（默认配置可能涉及较大范围的 UDP 端口，请根据实际情况调整）。
- **UDP 缓冲区优化**：为了获得最佳性能（特别是使用 Hysteria2/TUIC 时），建议在宿主机上增大 UDP 缓冲区大小。可以在宿主机执行以下命令：
  ```bash
  sudo sysctl -w net.core.rmem_max=8000000
  sudo sysctl -w net.core.wmem_max=8000000
  ```
