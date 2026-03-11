# EZProxy (Sing-Box Auto-Deploy)

基于 Docker 的 Sing-Box 自动部署工具，支持多种协议的一键配置与管理。

## ✨ 特性

- **多协议支持**：
  - ✅ **VLESS-Vision-uTLS-REALITY** (默认启用)
  - ✅ **Hysteria2** (默认启用)
  - ✅ **TUIC V5** (新增)
  - ❌ AnyTLS (开发中)
- **自动化配置**：
  - 自动生成 UUID 和密钥
  - 自动配置 SSL 证书 (自签名或 Let's Encrypt)
  - **自动生成全套客户端配置** (`client_config.json`)
  - 自动输出客户端分享链接
- **内置优化路由**：
  - 默认开启广告过滤 (`category-ads-all`)
  - 优化 DNS 路由逻辑

## 🚀 快速开始

### 0. 安装（Debian/Ubuntu）

```bash
git clone https://github.com/laomeifun/ezproxy
cd ezproxy
sudo bash install.sh
```

### 1. 获取配置与链接

首次启动后，可以通过以下命令查看分享链接：
```bash
docker compose exec ezproxy cat /etc/sing-box/share_links.txt
```

同时，项目会自动生成一个客户端配置文件模板：
```bash
docker compose exec ezproxy cat /etc/sing-box/conf/client_config.json
```
你可以直接将此 JSON 内容导入支持 sing-box 的客户端。

### 2. 配置说明

可以通过修改 `docker-compose.yaml` 中的环境变量来自定义：

```yaml
environment:
  - ENABLE_REALITY=1
  - ENABLE_HYSTERIA2=1
  - ENABLE_TUIC=1      # 启用 TUIC V5
  
  - REALITY_PORTS=443
  - HYSTERIA2_PORTS=50000
  - TUIC_PORTS=50001   # TUIC 端口
  
  - TUIC_CONGESTION=bbr # TUIC 拥塞控制 (bbr/cubic)
  
  - LE_MODE=selfsigned # 证书模式
```

## 📂 文件结构

- `data/conf`: 存放配置文件 (`config.json`, `client_config.json`) 和分享链接 (`share_links.txt`)
- `data/tls`: 存放证书文件
