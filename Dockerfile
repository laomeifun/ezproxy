FROM alpine:latest

LABEL maintainer="sing-box-auto-deploy"
LABEL description="Auto-deploy sing-box with VLESS-Reality, AnyTLS, Hysteria2, TUIC V5"

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    openssl \
    ca-certificates \
    tzdata \
    socat \
    certbot

# Set timezone
ENV TZ=UTC

# Create directories
RUN mkdir -p /etc/sing-box \
    /etc/sing-box/conf \
    /etc/sing-box/tls \
    /var/lib/sing-box \
    /app

# Download and install sing-box 1.12.0+ (supports anytls)
ARG SINGBOX_VERSION=1.12.13
RUN ARCH=$(uname -m) && \
    case "${ARCH}" in \
        x86_64|amd64) ARCH="amd64" ;; \
        aarch64|arm64) ARCH="arm64" ;; \
        armv7l) ARCH="armv7" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    echo "Downloading sing-box v${SINGBOX_VERSION} for ${ARCH}..." && \
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${ARCH}.tar.gz" \
    -o /tmp/sing-box.tar.gz && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-${SINGBOX_VERSION}-linux-${ARCH}/sing-box /usr/local/bin/ && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/* && \
    sing-box version

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Environment variables with defaults (empty means auto-generate)
# Protocol enable flags (1=enable, 0=disable, default all enabled)
ENV ENABLE_REALITY=1 \
    ENABLE_ANYTLS=1 \
    ENABLE_HYSTERIA2=1 \
    ENABLE_TUIC=1

# Ports (empty = random port between 10000-60000)
ENV REALITY_PORTS="" \
    ANYTLS_PORTS="" \
    HYSTERIA2_PORTS="" \
    TUIC_PORTS=""

# UUID (empty = auto-generate)
ENV UUID=""

# Reality settings
ENV REALITY_SERVER_NAME="" \
    REALITY_SERVER_PORT=443

# Hysteria2 settings
ENV HYSTERIA2_UP_MBPS=100 \
    HYSTERIA2_DOWN_MBPS=100

# TUIC settings
ENV TUIC_CONGESTION="bbr"

# Expose common port ranges
EXPOSE 10000-65535/tcp
EXPOSE 10000-65535/udp

WORKDIR /app

ENTRYPOINT ["/app/entrypoint.sh"]
