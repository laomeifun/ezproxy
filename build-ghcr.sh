#!/bin/bash

# GitHub Container Registry 构建脚本
# 使用方法: ./build-ghcr.sh [tag]

set -e

# 配置
REGISTRY="ghcr.io"
REPO_OWNER="${GITHUB_USER:-$(git config remote.origin.url | sed -n 's/.*github.com[:/]\([^/]*\)\/.*/\1/p')}"
REPO_NAME="$(basename $(git rev-parse --show-toplevel))"
IMAGE_NAME="${REGISTRY}/${REPO_OWNER}/${REPO_NAME}"
TAG="${1:-latest}"

echo "构建镜像: ${IMAGE_NAME}:${TAG}"

# 构建镜像
docker build -t "${IMAGE_NAME}:${TAG}" .

# 推送镜像
echo "推送镜像到 GitHub Container Registry..."
docker push "${IMAGE_NAME}:${TAG}"

echo "构建完成!"
echo "镜像地址: ${IMAGE_NAME}:${TAG}"
echo ""
echo "使用方法:"
echo "docker pull ${IMAGE_NAME}:${TAG}"
echo "docker run -d --name sing-box-auto --network host ${IMAGE_NAME}:${TAG}"