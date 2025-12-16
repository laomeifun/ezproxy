#!/bin/bash

# Docker自动安装和服务一键部署脚本
# 适用于Debian 12

set -e

# 获取命令行参数，设置 NAME_PREFIX，默认为 mo1
NAME_PREFIX=${1:-mo1}

echo "NAME_PREFIX 设置为: $NAME_PREFIX"
echo "开始安装Docker和Docker Compose..."

# 更新包索引
sudo apt update

# 安装必要的包
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 添加Docker官方GPG密钥
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 设置Docker稳定版仓库
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新包索引
sudo apt update

# 安装Docker Engine、CLI和Compose插件
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 启动Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户添加到docker组
sudo usermod -aG docker $USER

echo "Docker安装完成！"

# 等待Docker服务完全启动
sleep 5

# 检查Docker是否正常运行
if sudo docker --version; then
    echo "Docker运行正常"
else
    echo "Docker启动失败，请检查日志"
    exit 1
fi

# 创建docker-compose.yml文件
echo "创建docker-compose.yml文件..."
cat > docker-compose.yml << EOF
services:
  sing-box:
    image: ghcr.io/laomeifun/ezproxy:latest
    network_mode: host
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - NET_BIND_SERVICE
    volumes:
      - ./data/config:/etc/sing-box/conf
      - ./data/tls:/etc/sing-box/tls
      - ./data/letsencrypt:/etc/letsencrypt
    environment:
      - REUSE_CONFIG=1
      - NAME_PREFIX=${NAME_PREFIX}
      - ENABLE_REALITY=1
      - ENABLE_ANYTLS=1
      - ENABLE_HYSTERIA2=1
      - ENABLE_TUIC=1
      - REALITY_PORTS=7777
      - ANYTLS_PORTS=2053
      - HYSTERIA2_PORTS=8443
      - TUIC_PORTS=2096
EOF

echo "docker-compose.yml文件创建成功！"

# 启动docker-compose服务
echo "启动docker-compose服务..."
sudo docker compose up -d
echo "服务启动成功！"

# 等待服务启动
sleep 10

echo "=========================================="
echo "Docker容器日志输出："
echo "=========================================="

# 输出容器日志
sudo docker compose logs -f
