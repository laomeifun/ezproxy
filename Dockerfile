FROM ghcr.io/sagernet/sing-box:v1.12.13

LABEL maintainer="sing-box-auto-deploy"
LABEL description="Auto-deploy sing-box with VLESS-Reality, AnyTLS, Hysteria2, TUIC V5"

# Switch to root for installation
USER root

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

# Reuse persisted config in /etc/sing-box/conf if present (1=reuse, 0=regenerate)
ENV REUSE_CONFIG=1

# Custom domain (empty = use sslip.io auto-generated domain)
ENV CUSTOM_DOMAIN=""

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
