#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Reality server name options
REALITY_DOMAINS=(
    "gateway.icloud.com"
    "itunes.apple.com"
    "swdist.apple.com"
    "download-installer.cdn.mozilla.net"
    "addons.mozilla.org"
    "s0.awsstatic.com"
    "d1.awsstatic.com"
    "cdn-dynmedia-1.microsoft.com"
    "images-na.ssl-images-amazon.com"
    "www.lovelive-anime.jp"
    "academy.nvidia.com"
    "software.download.prss.microsoft.com"
    "dl.google.com"
    "www.google-analytics.com"
    "www.python.org"
    "vuejs.org"
    "react.dev"
    "www.java.com"
    "www.oracle.com"
    "www.mysql.com"
    "www.mongodb.com"
    "redis.io"
    "www.swift.com"
    "www.cisco.com"
    "www.asus.com"
    "www.samsung.com"
    "www.amd.com"
)

# Generate random port between 10000-60000
generate_random_port() {
    local used_ports="$1"
    local port
    while true; do
        port=$((RANDOM % 50001 + 10000))
        if [[ ! " ${used_ports} " =~ " ${port} " ]]; then
            echo "$port"
            return
        fi
    done
}

# Generate UUID
generate_uuid() {
    if command -v sing-box &> /dev/null; then
        sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate Reality keypair
generate_reality_keypair() {
    local result
    result=$(sing-box generate reality-keypair 2>/dev/null)
    if [[ -z "$result" ]]; then
        log_error "Failed to generate Reality keypair"
        exit 1
    fi
    echo "$result"
}

# Generate short ID
generate_short_id() {
    openssl rand -hex 8
}

# Get public IP
get_public_ip() {
    local ip=""
    # Try IPv4 first
    ip=$(curl -4 -s --connect-timeout 5 http://ifconfig.me 2>/dev/null || \
         curl -4 -s --connect-timeout 5 http://ipinfo.io/ip 2>/dev/null || \
         curl -4 -s --connect-timeout 5 http://api.ipify.org 2>/dev/null || \
         curl -4 -s --connect-timeout 5 http://icanhazip.com 2>/dev/null || \
         echo "")

    if [[ -z "$ip" ]]; then
        # Try IPv6
        ip=$(curl -6 -s --connect-timeout 5 http://ifconfig.me 2>/dev/null || \
             curl -6 -s --connect-timeout 5 http://api64.ipify.org 2>/dev/null || \
             echo "")
    fi

    echo "$ip"
}

# Get SSL certificate using sslip.io + Let's Encrypt
obtain_certificate() {
    local domain="$1"
    local cert_dir="/etc/sing-box/tls"
    local cert_obtained=0

    log_step "Obtaining SSL certificate for ${domain}..."

    # Ensure directory exists
    mkdir -p "${cert_dir}"

    # Check if certificate already exists and is valid
    if [[ -f "${cert_dir}/${domain}.crt" ]] && [[ -f "${cert_dir}/${domain}.key" ]]; then
        # Check if certificate is still valid (more than 7 days)
        if openssl x509 -checkend 604800 -noout -in "${cert_dir}/${domain}.crt" 2>/dev/null; then
            log_info "Valid certificate already exists for ${domain}"
            return 0
        else
            log_warn "Existing certificate is expiring, renewing..."
        fi
    fi

    # Try Let's Encrypt with standalone mode (requires port 80)
    log_info "Attempting to obtain Let's Encrypt certificate..."
    if certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --domain "${domain}" \
        --preferred-challenges http \
        --http-01-port 80 \
        2>&1; then
        cert_obtained=1
        log_info "Let's Encrypt certificate obtained successfully"
    else
        log_warn "Let's Encrypt standalone failed (port 80 might be in use)"
    fi

    # Copy from Let's Encrypt location if obtained
    if [[ "$cert_obtained" -eq 1 ]] && [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        cp -f "/etc/letsencrypt/live/${domain}/fullchain.pem" "${cert_dir}/${domain}.crt"
        cp -f "/etc/letsencrypt/live/${domain}/privkey.pem" "${cert_dir}/${domain}.key"
        log_info "Certificate copied to ${cert_dir}"
    fi

    # Fallback: generate self-signed certificate if Let's Encrypt failed
    if [[ ! -f "${cert_dir}/${domain}.crt" ]] || [[ ! -f "${cert_dir}/${domain}.key" ]]; then
        log_warn "Generating self-signed certificate as fallback..."
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "${cert_dir}/${domain}.key" \
            -out "${cert_dir}/${domain}.crt" \
            -days 365 -nodes \
            -subj "/CN=${domain}" \
            -addext "subjectAltName=DNS:${domain}" \
            2>/dev/null || \
        openssl req -x509 -newkey rsa:2048 \
            -keyout "${cert_dir}/${domain}.key" \
            -out "${cert_dir}/${domain}.crt" \
            -days 365 -nodes \
            -subj "/CN=${domain}" \
            2>/dev/null
        log_info "Self-signed certificate generated"
    fi

    # Set proper permissions
    chmod 600 "${cert_dir}/${domain}.key" 2>/dev/null || true
    chmod 644 "${cert_dir}/${domain}.crt" 2>/dev/null || true

    # Verify certificate files exist
    if [[ -f "${cert_dir}/${domain}.crt" ]] && [[ -f "${cert_dir}/${domain}.key" ]]; then
        log_info "Certificate ready for ${domain}"
        return 0
    else
        log_error "Failed to obtain or generate certificate for ${domain}"
        return 1
    fi
}

# Parse ports from environment variable (supports comma-separated values)
parse_ports() {
    local port_env="$1"
    local protocol="$2"
    local used_ports="$3"
    local ports=()

    if [[ -n "$port_env" ]]; then
        IFS=',' read -ra port_array <<< "$port_env"
        for p in "${port_array[@]}"; do
            p=$(echo "$p" | tr -d ' ')
            if [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -ge 1 ]] && [[ "$p" -le 65535 ]]; then
                ports+=("$p")
            fi
        done
    fi

    # If no valid ports, generate random one
    if [[ ${#ports[@]} -eq 0 ]]; then
        ports+=("$(generate_random_port "$used_ports")")
    fi

    echo "${ports[*]}"
}

# Select random Reality domain
select_reality_domain() {
    local idx=$((RANDOM % ${#REALITY_DOMAINS[@]}))
    echo "${REALITY_DOMAINS[$idx]}"
}

# Build inbound configuration for VLESS Reality
build_reality_inbound() {
    local port="$1"
    local uuid="$2"
    local server_name="$3"
    local server_port="$4"
    local private_key="$5"
    local short_id="$6"
    local tag="$7"

    cat <<EOF
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${port},
      "tag": "${tag}",
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision",
          "name": "reality-user"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${server_name}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${server_name}",
            "server_port": ${server_port}
          },
          "private_key": "${private_key}",
          "short_id": ["", "${short_id}"]
        }
      }
    }
EOF
}

# Build inbound configuration for AnyTLS
build_anytls_inbound() {
    local port="$1"
    local uuid="$2"
    local domain="$3"
    local tag="$4"

    cat <<EOF
    {
      "type": "anytls",
      "listen": "::",
      "listen_port": ${port},
      "tag": "${tag}",
      "users": [
        {
          "password": "${uuid}",
          "name": "anytls-user"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "certificate_path": "/etc/sing-box/tls/${domain}.crt",
        "key_path": "/etc/sing-box/tls/${domain}.key"
      }
    }
EOF
}

# Build inbound configuration for Hysteria2
build_hysteria2_inbound() {
    local port="$1"
    local uuid="$2"
    local domain="$3"
    local up_mbps="$4"
    local down_mbps="$5"
    local tag="$6"

    cat <<EOF
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": ${port},
      "tag": "${tag}",
      "users": [
        {
          "password": "${uuid}",
          "name": "hysteria2-user"
        }
      ],
      "up_mbps": ${up_mbps},
      "down_mbps": ${down_mbps},
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/tls/${domain}.crt",
        "key_path": "/etc/sing-box/tls/${domain}.key"
      }
    }
EOF
}

# Build inbound configuration for TUIC
build_tuic_inbound() {
    local port="$1"
    local uuid="$2"
    local domain="$3"
    local congestion="$4"
    local tag="$5"

    cat <<EOF
    {
      "type": "tuic",
      "listen": "::",
      "listen_port": ${port},
      "tag": "${tag}",
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}",
          "name": "tuic-user"
        }
      ],
      "congestion_control": "${congestion}",
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/tls/${domain}.crt",
        "key_path": "/etc/sing-box/tls/${domain}.key"
      }
    }
EOF
}

# URL encode function
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="$c" ;;
            * ) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

# Generate client configuration link
generate_share_link() {
    local protocol="$1"
    local server="$2"
    local port="$3"
    local uuid="$4"
    local extra="$5"

    # URL encode the UUID for safety
    local encoded_uuid=$(urlencode "$uuid")

    # Optional node name prefix (e.g. NAME_PREFIX=us1 -> us1-Reality-443)
    local name_prefix="${NAME_PREFIX:-}"
    if [[ -n "$name_prefix" && "$name_prefix" != *- ]]; then
        name_prefix="${name_prefix}-"
    fi

    case "$protocol" in
        "reality")
            local server_name=$(echo "$extra" | cut -d'|' -f1)
            local public_key=$(echo "$extra" | cut -d'|' -f2)
            local short_id=$(echo "$extra" | cut -d'|' -f3)
            local node_name="${name_prefix}Reality-${port}"
            local encoded_name=$(urlencode "$node_name")
            echo "vless://${encoded_uuid}@${server}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${encoded_name}"
            ;;
        "anytls")
            local domain=$(echo "$extra" | cut -d'|' -f1)
            local node_name="${name_prefix}AnyTLS-${port}"
            local encoded_name=$(urlencode "$node_name")
            echo "anytls://${encoded_uuid}@${server}:${port}?security=tls&sni=${domain}&allowInsecure=1#${encoded_name}"
            ;;
        "hysteria2")
            local domain=$(echo "$extra" | cut -d'|' -f1)
            local node_name="${name_prefix}Hysteria2-${port}"
            local encoded_name=$(urlencode "$node_name")
            echo "hysteria2://${encoded_uuid}@${server}:${port}?sni=${domain}&alpn=h3&insecure=1#${encoded_name}"
            ;;
        "tuic")
            local domain=$(echo "$extra" | cut -d'|' -f1)
            local congestion=$(echo "$extra" | cut -d'|' -f2)
            local node_name="${name_prefix}TUIC-${port}"
            local encoded_name=$(urlencode "$node_name")
            echo "tuic://${encoded_uuid}:${encoded_uuid}@${server}:${port}?sni=${domain}&congestion_control=${congestion}&alpn=h3&allow_insecure=1#${encoded_name}"
            ;;
    esac
}

# Main function
main() {
    log_step "Starting sing-box auto-deployment..."

    # Get public IP
    log_step "Detecting public IP..."
    PUBLIC_IP=$(get_public_ip)
    if [[ -z "$PUBLIC_IP" ]]; then
        log_error "Failed to detect public IP"
        exit 1
    fi
    log_info "Public IP: ${PUBLIC_IP}"

    # Determine TLS domain - use custom domain if provided, otherwise sslip.io
    if [[ -n "$CUSTOM_DOMAIN" ]]; then
        TLS_DOMAIN="$CUSTOM_DOMAIN"
        log_info "Using custom domain: ${TLS_DOMAIN}"
    else
        # Generate sslip.io domain as fallback
        TLS_DOMAIN="${PUBLIC_IP//./-}.sslip.io"
        if [[ "$PUBLIC_IP" == *":"* ]]; then
            # IPv6 - replace colons with dashes
            TLS_DOMAIN="${PUBLIC_IP//:/-}.sslip.io"
        fi
        log_info "Using sslip.io domain: ${TLS_DOMAIN}"
    fi

    # Keep SSL_DOMAIN for backward compatibility
    SSL_DOMAIN="$TLS_DOMAIN"

    # Generate or use existing UUID
    if [[ -z "$UUID" ]]; then
        UUID=$(generate_uuid)
        log_info "Generated UUID: ${UUID}"
    else
        log_info "Using provided UUID: ${UUID}"
    fi

    # Generate Reality keypair
    log_step "Generating Reality keypair..."
    REALITY_KEYPAIR=$(generate_reality_keypair)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYPAIR" | grep "PrivateKey" | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYPAIR" | grep "PublicKey" | awk '{print $2}')
    REALITY_SHORT_ID=$(generate_short_id)
    log_info "Reality Public Key: ${REALITY_PUBLIC_KEY}"

    # Select Reality server name
    if [[ -z "$REALITY_SERVER_NAME" ]] || [[ "$REALITY_SERVER_NAME" == "www.microsoft.com" ]]; then
        REALITY_SERVER_NAME=$(select_reality_domain)
    fi
    log_info "Reality Server Name: ${REALITY_SERVER_NAME}"

    # Track used ports
    USED_PORTS=""

    # Initialize inbounds array
    INBOUNDS=""
    SHARE_LINKS=""

    # Process Reality protocol
    if [[ "$ENABLE_REALITY" == "1" ]]; then
        log_step "Configuring VLESS-Reality-Vision..."

        REALITY_PORT_LIST=$(parse_ports "$REALITY_PORTS" "reality" "$USED_PORTS")
        read -ra REALITY_PORTS_ARRAY <<< "$REALITY_PORT_LIST"

        for i in "${!REALITY_PORTS_ARRAY[@]}"; do
            port="${REALITY_PORTS_ARRAY[$i]}"
            USED_PORTS="$USED_PORTS $port"
            tag="vless-reality-$i"

            inbound=$(build_reality_inbound "$port" "$UUID" "$REALITY_SERVER_NAME" "${REALITY_SERVER_PORT:-443}" "$REALITY_PRIVATE_KEY" "$REALITY_SHORT_ID" "$tag")

            if [[ -n "$INBOUNDS" ]]; then
                INBOUNDS="${INBOUNDS},"
            fi
            INBOUNDS="${INBOUNDS}${inbound}"

            link=$(generate_share_link "reality" "$PUBLIC_IP" "$port" "$UUID" "${REALITY_SERVER_NAME}|${REALITY_PUBLIC_KEY}|${REALITY_SHORT_ID}")
            SHARE_LINKS="${SHARE_LINKS}\n${link}"

            log_info "Reality port ${port} configured"
        done
    fi

    # Process AnyTLS, Hysteria2, TUIC (require TLS certificate)
    NEED_CERT=0
    if [[ "$ENABLE_ANYTLS" == "1" ]] || [[ "$ENABLE_HYSTERIA2" == "1" ]] || [[ "$ENABLE_TUIC" == "1" ]]; then
        NEED_CERT=1
    fi

    if [[ "$NEED_CERT" == "1" ]]; then
        obtain_certificate "$SSL_DOMAIN"
    fi

    # Process AnyTLS protocol
    if [[ "$ENABLE_ANYTLS" == "1" ]]; then
        log_step "Configuring AnyTLS..."

        ANYTLS_PORT_LIST=$(parse_ports "$ANYTLS_PORTS" "anytls" "$USED_PORTS")
        read -ra ANYTLS_PORTS_ARRAY <<< "$ANYTLS_PORT_LIST"

        for i in "${!ANYTLS_PORTS_ARRAY[@]}"; do
            port="${ANYTLS_PORTS_ARRAY[$i]}"
            USED_PORTS="$USED_PORTS $port"
            tag="anytls-$i"

            inbound=$(build_anytls_inbound "$port" "$UUID" "$SSL_DOMAIN" "$tag")

            if [[ -n "$INBOUNDS" ]]; then
                INBOUNDS="${INBOUNDS},"
            fi
            INBOUNDS="${INBOUNDS}${inbound}"

            link=$(generate_share_link "anytls" "$PUBLIC_IP" "$port" "$UUID" "${SSL_DOMAIN}")
            SHARE_LINKS="${SHARE_LINKS}\n${link}"

            log_info "AnyTLS port ${port} configured"
        done
    fi

    # Process Hysteria2 protocol
    if [[ "$ENABLE_HYSTERIA2" == "1" ]]; then
        log_step "Configuring Hysteria2..."

        HYSTERIA2_PORT_LIST=$(parse_ports "$HYSTERIA2_PORTS" "hysteria2" "$USED_PORTS")
        read -ra HYSTERIA2_PORTS_ARRAY <<< "$HYSTERIA2_PORT_LIST"

        for i in "${!HYSTERIA2_PORTS_ARRAY[@]}"; do
            port="${HYSTERIA2_PORTS_ARRAY[$i]}"
            USED_PORTS="$USED_PORTS $port"
            tag="hysteria2-$i"

            inbound=$(build_hysteria2_inbound "$port" "$UUID" "$SSL_DOMAIN" "${HYSTERIA2_UP_MBPS:-100}" "${HYSTERIA2_DOWN_MBPS:-100}" "$tag")

            if [[ -n "$INBOUNDS" ]]; then
                INBOUNDS="${INBOUNDS},"
            fi
            INBOUNDS="${INBOUNDS}${inbound}"

            link=$(generate_share_link "hysteria2" "$PUBLIC_IP" "$port" "$UUID" "${SSL_DOMAIN}")
            SHARE_LINKS="${SHARE_LINKS}\n${link}"

            log_info "Hysteria2 port ${port} configured"
        done
    fi

    # Process TUIC protocol
    if [[ "$ENABLE_TUIC" == "1" ]]; then
        log_step "Configuring TUIC V5..."

        TUIC_PORT_LIST=$(parse_ports "$TUIC_PORTS" "tuic" "$USED_PORTS")
        read -ra TUIC_PORTS_ARRAY <<< "$TUIC_PORT_LIST"

        for i in "${!TUIC_PORTS_ARRAY[@]}"; do
            port="${TUIC_PORTS_ARRAY[$i]}"
            USED_PORTS="$USED_PORTS $port"
            tag="tuic-$i"

            inbound=$(build_tuic_inbound "$port" "$UUID" "$SSL_DOMAIN" "${TUIC_CONGESTION:-bbr}" "$tag")

            if [[ -n "$INBOUNDS" ]]; then
                INBOUNDS="${INBOUNDS},"
            fi
            INBOUNDS="${INBOUNDS}${inbound}"

            link=$(generate_share_link "tuic" "$PUBLIC_IP" "$port" "$UUID" "${SSL_DOMAIN}|${TUIC_CONGESTION:-bbr}")
            SHARE_LINKS="${SHARE_LINKS}\n${link}"

            log_info "TUIC port ${port} configured"
        done
    fi

    # Generate sing-box configuration
    log_step "Generating sing-box configuration..."

    cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google-dns",
        "address": "https://8.8.8.8/dns-query",
        "address_resolver": "local-dns"
      },
      {
        "tag": "local-dns",
        "address": "local"
      }
    ]
  },
  "inbounds": [
${INBOUNDS}
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out",
      "domain_resolver": "local-dns"
    }
  ],
  "route": {
    "default_domain_resolver": "local-dns",
    "final": "direct-out"
  }
}
EOF

    # Validate configuration
    log_step "Validating configuration..."
    if sing-box check -c /etc/sing-box/config.json; then
        log_info "Configuration is valid"
    else
        log_error "Configuration validation failed"
        cat /etc/sing-box/config.json
        exit 1
    fi

    # Print share links
    echo ""
    echo "=============================================="
    echo "         DEPLOYMENT COMPLETE"
    echo "=============================================="
    echo ""
    echo "Server: ${PUBLIC_IP}"
    echo "UUID: ${UUID}"
    if [[ -n "$CUSTOM_DOMAIN" ]]; then
        echo "TLS Domain: ${TLS_DOMAIN} (custom)"
    else
        echo "TLS Domain: ${TLS_DOMAIN} (sslip.io auto)"
    fi
    echo ""

    if [[ "$ENABLE_REALITY" == "1" ]]; then
        echo "=== VLESS-Reality-Vision ==="
        echo "Server: ${PUBLIC_IP}"
        echo "Server Name (SNI): ${REALITY_SERVER_NAME}"
        echo "Public Key: ${REALITY_PUBLIC_KEY}"
        echo "Short ID: ${REALITY_SHORT_ID}"
        echo "Ports: ${REALITY_PORT_LIST}"
        echo ""
    fi

    if [[ "$ENABLE_ANYTLS" == "1" ]]; then
        echo "=== AnyTLS ==="
        echo "Server: ${PUBLIC_IP}"
        echo "SNI: ${TLS_DOMAIN}"
        echo "Ports: ${ANYTLS_PORT_LIST}"
        echo ""
    fi

    if [[ "$ENABLE_HYSTERIA2" == "1" ]]; then
        echo "=== Hysteria2 ==="
        echo "Server: ${PUBLIC_IP}"
        echo "SNI: ${TLS_DOMAIN}"
        echo "Ports: ${HYSTERIA2_PORT_LIST}"
        echo "Up/Down: ${HYSTERIA2_UP_MBPS:-100}/${HYSTERIA2_DOWN_MBPS:-100} Mbps"
        echo ""
    fi

    if [[ "$ENABLE_TUIC" == "1" ]]; then
        echo "=== TUIC V5 ==="
        echo "Server: ${PUBLIC_IP}"
        echo "SNI: ${TLS_DOMAIN}"
        echo "Ports: ${TUIC_PORT_LIST}"
        echo "Congestion: ${TUIC_CONGESTION:-bbr}"
        echo ""
    fi

    echo "=============================================="
    echo "         SHARE LINKS"
    echo "=============================================="
    echo -e "$SHARE_LINKS"
    echo ""
    echo "=============================================="

    # Save share links to file
    echo -e "$SHARE_LINKS" > /etc/sing-box/share_links.txt

    # Save complete deployment info to JSON file
    log_step "Saving deployment information..."
    cat > /etc/sing-box/deployment_info.json <<EOFINFO
{
  "server_ip": "${PUBLIC_IP}",
  "tls_domain": "${TLS_DOMAIN}",
  "custom_domain": "${CUSTOM_DOMAIN:-}",
  "uuid": "${UUID}",
  "deployed_at": "$(date -Iseconds)",
  "protocols": {
    "reality": {
      "enabled": ${ENABLE_REALITY},
      "server": "${PUBLIC_IP}",
      "server_name": "${REALITY_SERVER_NAME}",
      "server_port": ${REALITY_SERVER_PORT:-443},
      "public_key": "${REALITY_PUBLIC_KEY}",
      "private_key": "${REALITY_PRIVATE_KEY}",
      "short_id": "${REALITY_SHORT_ID}",
      "ports": "${REALITY_PORT_LIST:-}"
    },
    "anytls": {
      "enabled": ${ENABLE_ANYTLS},
      "server": "${PUBLIC_IP}",
      "sni": "${TLS_DOMAIN}",
      "ports": "${ANYTLS_PORT_LIST:-}"
    },
    "hysteria2": {
      "enabled": ${ENABLE_HYSTERIA2},
      "server": "${PUBLIC_IP}",
      "sni": "${TLS_DOMAIN}",
      "up_mbps": ${HYSTERIA2_UP_MBPS:-100},
      "down_mbps": ${HYSTERIA2_DOWN_MBPS:-100},
      "ports": "${HYSTERIA2_PORT_LIST:-}"
    },
    "tuic": {
      "enabled": ${ENABLE_TUIC},
      "server": "${PUBLIC_IP}",
      "sni": "${TLS_DOMAIN}",
      "congestion": "${TUIC_CONGESTION:-bbr}",
      "ports": "${TUIC_PORT_LIST:-}"
    }
  }
}
EOFINFO

    log_info "Deployment info saved to /etc/sing-box/deployment_info.json"
    log_info "Share links saved to /etc/sing-box/share_links.txt"

    # Start sing-box
    log_step "Starting sing-box..."
    exec sing-box run -c /etc/sing-box/config.json
}

# Run main function
main "$@"
