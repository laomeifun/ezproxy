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

PERSIST_DIR="/etc/sing-box/conf"
PERSIST_CONFIG="${PERSIST_DIR}/config.json"
PERSIST_SHARE_LINKS="${PERSIST_DIR}/share_links.txt"
PERSIST_INFO="${PERSIST_DIR}/deployment_info.json"
REUSE_CONFIG_DEFAULT=1

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

# Get public IPv4
get_public_ipv4() {
    local ip=""
    ip=$(curl -4 -s --connect-timeout 5 http://ifconfig.me 2>/dev/null || \
         curl -4 -s --connect-timeout 5 http://ipinfo.io/ip 2>/dev/null || \
         curl -4 -s --connect-timeout 5 http://api.ipify.org 2>/dev/null || \
         curl -4 -s --connect-timeout 5 http://icanhazip.com 2>/dev/null || \
         echo "")
    echo "$ip"
}

# Get public IPv6
get_public_ipv6() {
    local ip=""
    ip=$(curl -6 -s --connect-timeout 5 http://ifconfig.me 2>/dev/null || \
         curl -6 -s --connect-timeout 5 http://api64.ipify.org 2>/dev/null || \
         curl -6 -s --connect-timeout 5 http://icanhazip.com 2>/dev/null || \
         echo "")
    echo "$ip"
}

# Get public IP (prefer IPv4)
get_public_ip() {
    local ip=""
    ip=$(get_public_ipv4)
    if [[ -z "$ip" ]]; then
        ip=$(get_public_ipv6)
    fi
    echo "$ip"
}

# Get SSL certificate using sslip.io + Let's Encrypt
obtain_certificate() {
    local domain="$1"
    local cert_dir="/etc/sing-box/tls"
    local cert_obtained=0

    local le_mode="${LE_MODE:-auto}"
    case "${le_mode}" in
        auto|selfsigned|letsencrypt)
            ;;
        *)
            log_warn "Unknown LE_MODE='${le_mode}', falling back to 'auto'"
            le_mode="auto"
            ;;
    esac

    log_step "Obtaining SSL certificate for ${domain}..."

    # Debug: show what exists in the tls directory
    log_info "Checking TLS directory ${cert_dir}:"
    ls -la "${cert_dir}/" 2>/dev/null || log_warn "Cannot list ${cert_dir}"

    # Check for mounted certificate files (don't mkdir if files are already mounted)
    local cert_path="${cert_dir}/${domain}.crt"
    local key_path="${cert_dir}/${domain}.key"

    # Debug: check file status
    if [[ -e "${cert_path}" ]]; then
        if [[ -f "${cert_path}" ]]; then
            log_info "Certificate file exists: ${cert_path}"
        elif [[ -d "${cert_path}" ]]; then
            log_error "Certificate path is a DIRECTORY (not a file): ${cert_path}"
            log_error "This usually happens when Docker creates a directory instead of mounting a file."
            log_error "Check that the source file exists on the host before starting the container."
            return 1
        else
            log_warn "Certificate path exists but is not a regular file: ${cert_path}"
        fi
    else
        log_info "Certificate file does not exist: ${cert_path}"
    fi

    if [[ -e "${key_path}" ]]; then
        if [[ -f "${key_path}" ]]; then
            log_info "Key file exists: ${key_path}"
        elif [[ -d "${key_path}" ]]; then
            log_error "Key path is a DIRECTORY (not a file): ${key_path}"
            log_error "This usually happens when Docker creates a directory instead of mounting a file."
            log_error "Check that the source file exists on the host before starting the container."
            return 1
        else
            log_warn "Key path exists but is not a regular file: ${key_path}"
        fi
    else
        log_info "Key file does not exist: ${key_path}"
    fi

    # Ensure directory exists (only if not mounting individual files)
    if [[ ! -d "${cert_dir}" ]]; then
        mkdir -p "${cert_dir}"
    fi

    # If cert/key exist but are not readable, fail fast with a clear hint.
    if [[ -f "${cert_path}" ]] && [[ ! -r "${cert_path}" ]]; then
        log_error "Certificate exists but is not readable: ${cert_path}"
        log_error "Fix by running container as root (docker-compose: user: \"0:0\") or relaxing file permissions on the host."
        return 1
    fi
    if [[ -f "${key_path}" ]] && [[ ! -r "${key_path}" ]]; then
        log_error "Private key exists but is not readable: ${key_path}"
        log_error "Fix by running container as root (docker-compose: user: \"0:0\") or adjusting host file permissions/ownership."
        return 1
    fi

    # Check if certificate already exists and is valid
    if [[ -f "${cert_path}" ]] && [[ -f "${key_path}" ]]; then
        # Check if files are read-only (likely mounted externally)
        local is_readonly=0
        if [[ ! -w "${cert_path}" ]] || [[ ! -w "${key_path}" ]]; then
            is_readonly=1
            log_info "Certificate files are read-only (mounted externally)"
        fi

        # Check if certificate is currently valid
        if openssl x509 -checkend 0 -noout -in "${cert_path}" 2>/dev/null; then
            # Prefer reusing an existing valid cert, especially when running in selfsigned mode
            # or when cert/key paths may be mounted read-only.
            if openssl x509 -checkend 604800 -noout -in "${cert_path}" 2>/dev/null; then
                log_info "Valid certificate already exists for ${domain}"
                return 0
            fi

            if [[ "${le_mode}" == "selfsigned" ]] || [[ "$is_readonly" -eq 1 ]]; then
                log_warn "Certificate exists and is currently valid but expires soon; reusing existing certificate (LE_MODE=${le_mode}, readonly=${is_readonly})"
                return 0
            fi

            log_warn "Existing certificate is expiring soon, attempting renewal..."
        else
            # Certificate is expired or invalid
            if [[ "$is_readonly" -eq 1 ]]; then
                log_error "Existing certificate is expired or invalid, but files are read-only (mounted externally)."
                log_error "Please ensure the mounted certificate at ${cert_path} is valid."
                log_error "Check with: openssl x509 -noout -dates -in /path/to/your/cert.pem"
                return 1
            fi

            if [[ "${le_mode}" == "selfsigned" ]]; then
                log_warn "Existing certificate is expired or invalid; will regenerate self-signed certificate..."
            else
                log_warn "Existing certificate is expired or invalid, attempting renewal..."
            fi
        fi
    fi

    # Try Let's Encrypt with standalone mode (requires port 80)
    if [[ "${le_mode}" != "selfsigned" ]]; then
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
            if [[ "${le_mode}" == "letsencrypt" ]]; then
                log_error "Let's Encrypt failed and LE_MODE=letsencrypt is set (no self-signed fallback)."
                return 1
            fi
            log_warn "Let's Encrypt standalone failed (port 80 might be in use)"
        fi
    else
        log_info "LE_MODE=selfsigned set; skipping Let's Encrypt attempt"
    fi

    # Copy from Let's Encrypt location if obtained
    if [[ "$cert_obtained" -eq 1 ]] && [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        cp -f "/etc/letsencrypt/live/${domain}/fullchain.pem" "${cert_path}"
        cp -f "/etc/letsencrypt/live/${domain}/privkey.pem" "${key_path}"
        log_info "Certificate copied to ${cert_dir}"
    fi

    # Fallback: generate self-signed certificate if Let's Encrypt failed
    if [[ ! -f "${cert_path}" ]] || [[ ! -f "${key_path}" ]]; then
        log_warn "Generating self-signed certificate as fallback..."

        # If target paths are mounted read-only or are directories, fail fast with a clear hint.
        if [[ -d "${cert_path}" ]] || [[ -d "${key_path}" ]]; then
            log_error "Certificate/key paths are directories instead of files!"
            log_error "This happens when Docker creates directories because the source files don't exist on the host."
            log_error "Make sure the certificate files exist on the host BEFORE starting the container."
            return 1
        fi

        if { [[ -e "${cert_path}" ]] && [[ ! -w "${cert_path}" ]]; } || \
           { [[ -e "${key_path}" ]] && [[ ! -w "${key_path}" ]]; }; then
            log_error "Cannot write self-signed certificate to ${cert_path}/.key (path is read-only)."
            log_error "If you mounted external certs with ':ro', ensure the existing cert is valid and will be reused, or mount a writable directory for /etc/sing-box/tls."
            return 1
        fi

        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "${key_path}" \
            -out "${cert_path}" \
            -days 365 -nodes \
            -subj "/CN=${domain}" \
            -addext "subjectAltName=DNS:${domain}" \
            2>/dev/null || \
        openssl req -x509 -newkey rsa:2048 \
            -keyout "${key_path}" \
            -out "${cert_path}" \
            -days 365 -nodes \
            -subj "/CN=${domain}" \
            2>/dev/null
        log_info "Self-signed certificate generated"
    fi

    # Set proper permissions
    chmod 600 "${key_path}" 2>/dev/null || true
    chmod 644 "${cert_path}" 2>/dev/null || true

    # Verify certificate files exist
    if [[ -f "${cert_path}" ]] && [[ -f "${key_path}" ]]; then
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

# Build inbound configuration for Hysteria2
build_hysteria2_inbound() {
    local port="$1"
    local uuid="$2"
    local domain="$3"
    local up_mbps="$4"
    local down_mbps="$5"
    local obfs_password="$6"
    local tag="$7"

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
      "obfs": {
        "type": "salamander",
        "password": "${obfs_password}"
      },
      "tls": {
        "enabled": true,
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
# Args: protocol, server, port, uuid, extra, suffix (optional, e.g. "-ipv6")
generate_share_link() {
    local protocol="$1"
    local server="$2"
    local port="$3"
    local uuid="$4"
    local extra="$5"
    local suffix="${6:-}"  # Optional suffix like "-ipv6"

    # URL encode the UUID for safety
    local encoded_uuid=$(urlencode "$uuid")

    # Use hostname as node name prefix
    local name_prefix="${NODE_NAME:-$(hostname 2>/dev/null || echo 'node')}"
    # Clean up hostname (remove domain part if exists)
    name_prefix="${name_prefix%%.*}"

    case "$protocol" in
        "reality")
            local server_name=$(echo "$extra" | cut -d'|' -f1)
            local public_key=$(echo "$extra" | cut -d'|' -f2)
            local short_id=$(echo "$extra" | cut -d'|' -f3)
            local node_name="${name_prefix}-Reality-${port}${suffix}"
            local encoded_name=$(urlencode "$node_name")
            # For IPv6 server, wrap in brackets
            local server_addr="$server"
            if [[ "$server" == *":"* ]]; then
                server_addr="[${server}]"
            fi
            echo "vless://${encoded_uuid}@${server_addr}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${encoded_name}"
            ;;
        "hysteria2")
            local domain=$(echo "$extra" | cut -d'|' -f1)
            local obfs_password=$(echo "$extra" | cut -d'|' -f2)
            local ports=$(echo "$extra" | cut -d'|' -f3)
            
            local node_name="${name_prefix}-Hysteria2-${port}${suffix}"
            local encoded_name=$(urlencode "$node_name")
            # For IPv6 server, wrap in brackets
            local server_addr="$server"
            if [[ "$server" == *":"* ]]; then
                server_addr="[${server}]"
            fi
            
            local link="hysteria2://${encoded_uuid}@${server_addr}:${port}?sni=${domain}&alpn=h3&insecure=1&obfs=salamander&obfs-password=${obfs_password}"
            if [[ -n "$ports" ]]; then
                link="${link}&mport=${ports}"
            fi
            echo "${link}#${encoded_name}"
            ;;
    esac
}

# Main function
main() {
    log_step "Starting sing-box auto-deployment..."

    # Force self-signed certificate
    export LE_MODE="selfsigned"

    mkdir -p "${PERSIST_DIR}" 2>/dev/null || true

    # By default, reuse persisted config if present.
    # Set REUSE_CONFIG=0 to force regeneration from environment variables.
    local reuse_config="${REUSE_CONFIG:-$REUSE_CONFIG_DEFAULT}"
    if [[ "${reuse_config}" != "0" ]] && [[ -f "${PERSIST_CONFIG}" ]]; then
        log_info "Found persisted config at ${PERSIST_CONFIG}; attempting to reuse existing configuration"

        # Keep legacy paths for healthcheck/commands
        ln -sf "${PERSIST_CONFIG}" /etc/sing-box/config.json
        if [[ -f "${PERSIST_SHARE_LINKS}" ]]; then
            ln -sf "${PERSIST_SHARE_LINKS}" /etc/sing-box/share_links.txt
        fi
        if [[ -f "${PERSIST_INFO}" ]]; then
            ln -sf "${PERSIST_INFO}" /etc/sing-box/deployment_info.json
        fi

        if sing-box check -c "${PERSIST_CONFIG}"; then
            log_step "Starting sing-box..."
            exec sing-box run -c "${PERSIST_CONFIG}"
        else
            log_warn "Persisted config validation failed; regenerating configuration from environment"
        fi
    fi

    # Get public IP (IPv4 and IPv6)
    log_step "Detecting public IP..."
    PUBLIC_IPV4=$(get_public_ipv4)
    PUBLIC_IPV6=$(get_public_ipv6)
    
    if [[ -n "$PUBLIC_IPV4" ]]; then
        log_info "Public IPv4: ${PUBLIC_IPV4}"
    else
        log_warn "No IPv4 address detected"
    fi
    
    if [[ -n "$PUBLIC_IPV6" ]]; then
        log_info "Public IPv6: ${PUBLIC_IPV6}"
    else
        log_warn "No IPv6 address detected"
    fi
    
    # Use IPv4 as primary, fallback to IPv6
    if [[ -n "$PUBLIC_IPV4" ]]; then
        PUBLIC_IP="$PUBLIC_IPV4"
    elif [[ -n "$PUBLIC_IPV6" ]]; then
        PUBLIC_IP="$PUBLIC_IPV6"
    else
        log_error "Failed to detect any public IP"
        exit 1
    fi
    log_info "Primary IP: ${PUBLIC_IP}"
    
    # Get hostname for node naming
    NODE_NAME="${NODE_NAME:-$(hostname 2>/dev/null || echo 'node')}"
    NODE_NAME="${NODE_NAME%%.*}"  # Remove domain part
    log_info "Node name: ${NODE_NAME}"

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

        # Default to 443 if not set
        if [[ -z "$REALITY_PORTS" ]]; then
            REALITY_PORTS="443"
        fi

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

            # Generate IPv4 share link
            if [[ -n "$PUBLIC_IPV4" ]]; then
                link=$(generate_share_link "reality" "$PUBLIC_IPV4" "$port" "$UUID" "${REALITY_SERVER_NAME}|${REALITY_PUBLIC_KEY}|${REALITY_SHORT_ID}" "")
                SHARE_LINKS="${SHARE_LINKS}\n${link}"
            fi
            
            # Generate IPv6 share link with -ipv6 suffix
            if [[ -n "$PUBLIC_IPV6" ]]; then
                link_v6=$(generate_share_link "reality" "$PUBLIC_IPV6" "$port" "$UUID" "${REALITY_SERVER_NAME}|${REALITY_PUBLIC_KEY}|${REALITY_SHORT_ID}" "-ipv6")
                SHARE_LINKS="${SHARE_LINKS}\n${link_v6}"
            fi

            log_info "Reality port ${port} configured"
        done
    fi

    # Process Hysteria2 (require TLS certificate)
    NEED_CERT=0
    if [[ "$ENABLE_HYSTERIA2" == "1" ]]; then
        NEED_CERT=1
    fi

    if [[ "$NEED_CERT" == "1" ]]; then
        obtain_certificate "$SSL_DOMAIN"
    fi

    # Process Hysteria2 protocol
    if [[ "$ENABLE_HYSTERIA2" == "1" ]]; then
        log_step "Configuring Hysteria2..."

        # Default to 50000 if not set
        if [[ -z "$HYSTERIA2_PORTS" ]]; then
            HYSTERIA2_PORTS="50000"
        fi

        # Generate Obfs Password
        HYSTERIA2_OBFS_PASSWORD=$(openssl rand -hex 16)

        HYSTERIA2_PORT_LIST=$(parse_ports "$HYSTERIA2_PORTS" "hysteria2" "$USED_PORTS")
        read -ra HYSTERIA2_PORTS_ARRAY <<< "$HYSTERIA2_PORT_LIST"

        for i in "${!HYSTERIA2_PORTS_ARRAY[@]}"; do
            port="${HYSTERIA2_PORTS_ARRAY[$i]}"
            USED_PORTS="$USED_PORTS $port"
            tag="hysteria2-$i"

            inbound=$(build_hysteria2_inbound "$port" "$UUID" "$SSL_DOMAIN" "${HYSTERIA2_UP_MBPS:-100}" "${HYSTERIA2_DOWN_MBPS:-100}" "$HYSTERIA2_OBFS_PASSWORD" "$tag")

            if [[ -n "$INBOUNDS" ]]; then
                INBOUNDS="${INBOUNDS},"
            fi
            INBOUNDS="${INBOUNDS}${inbound}"

            # Determine port hopping range
            local hopping_ports=""
            if [[ "$port" == "50000" ]]; then
                hopping_ports="20000-45000"
            fi

            # Generate IPv4 share link (use real SNI for Salamander obfs)
            if [[ -n "$PUBLIC_IPV4" ]]; then
                link=$(generate_share_link "hysteria2" "$PUBLIC_IPV4" "$port" "$UUID" "${TLS_DOMAIN}|${HYSTERIA2_OBFS_PASSWORD}|${hopping_ports}" "")
                SHARE_LINKS="${SHARE_LINKS}\n${link}"
            fi
            
            # Generate IPv6 share link with -ipv6 suffix
            if [[ -n "$PUBLIC_IPV6" ]]; then
                link_v6=$(generate_share_link "hysteria2" "$PUBLIC_IPV6" "$port" "$UUID" "${TLS_DOMAIN}|${HYSTERIA2_OBFS_PASSWORD}|${hopping_ports}" "-ipv6")
                SHARE_LINKS="${SHARE_LINKS}\n${link_v6}"
            fi

            log_info "Hysteria2 port ${port} configured"
            
            # Add iptables rule for port hopping if port is 50000
            if [[ "$port" == "50000" ]]; then
                log_info "Setting up iptables for Hysteria2 port hopping (20000-45000 -> 50000)..."
                if command -v iptables &> /dev/null; then
                    # Remove existing rule first to prevent duplicates (idempotency)
                    iptables -t nat -D PREROUTING -p udp --dport 20000:45000 -j REDIRECT --to-ports 50000 2>/dev/null || true
                    
                    if iptables -t nat -A PREROUTING -p udp --dport 20000:45000 -j REDIRECT --to-ports 50000; then
                        log_info "iptables rule added successfully"
                    else
                        log_warn "Failed to set iptables rule"
                    fi
                else
                    log_warn "iptables not found, port hopping redirection might not work"
                fi
            fi
        done
    fi

    # Generate sing-box configuration
    log_step "Generating sing-box configuration..."

        umask 077
        cat > "${PERSIST_CONFIG}" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
${INBOUNDS}
  ],
  "outbounds": [
    {
      "type": "direct",
            "tag": "direct-out"
    }
  ],
  "route": {
    "final": "direct-out"
  }
}
EOF

    # Validate configuration
    log_step "Validating configuration..."
    if sing-box check -c "${PERSIST_CONFIG}"; then
        log_info "Configuration is valid"
    else
        log_error "Configuration validation failed"
        cat "${PERSIST_CONFIG}"
        exit 1
    fi

    # Keep legacy path for healthcheck/commands
    ln -sf "${PERSIST_CONFIG}" /etc/sing-box/config.json

    # Print share links
    echo ""
    echo "=============================================="
    echo "         DEPLOYMENT COMPLETE"
    echo "=============================================="
    echo ""
    echo "Node Name: ${NODE_NAME}"
    if [[ -n "$PUBLIC_IPV4" ]]; then
        echo "IPv4: ${PUBLIC_IPV4}"
    fi
    if [[ -n "$PUBLIC_IPV6" ]]; then
        echo "IPv6: ${PUBLIC_IPV6}"
    fi
    echo "UUID: ${UUID}"
    if [[ -n "$CUSTOM_DOMAIN" ]]; then
        echo "TLS Domain: ${TLS_DOMAIN} (custom)"
    else
        echo "TLS Domain: ${TLS_DOMAIN} (sslip.io auto)"
    fi
    echo ""

    if [[ "$ENABLE_REALITY" == "1" ]]; then
        echo "=== VLESS-Reality-Vision ==="
        if [[ -n "$PUBLIC_IPV4" ]]; then
            echo "Server (IPv4): ${PUBLIC_IPV4}"
        fi
        if [[ -n "$PUBLIC_IPV6" ]]; then
            echo "Server (IPv6): ${PUBLIC_IPV6}"
        fi
        echo "Server Name (SNI): ${REALITY_SERVER_NAME}"
        echo "Public Key: ${REALITY_PUBLIC_KEY}"
        echo "Short ID: ${REALITY_SHORT_ID}"
        echo "Ports: ${REALITY_PORT_LIST}"
        echo ""
    fi

    if [[ "$ENABLE_HYSTERIA2" == "1" ]]; then
        echo "=== Hysteria2 ==="
        if [[ -n "$PUBLIC_IPV4" ]]; then
            echo "Server (IPv4): ${PUBLIC_IPV4}"
        fi
        if [[ -n "$PUBLIC_IPV6" ]]; then
            echo "Server (IPv6): ${PUBLIC_IPV6}"
        fi
        echo "SNI: ${TLS_DOMAIN}"
        echo "Ports: ${HYSTERIA2_PORT_LIST}"
        echo "Port Hopping: 20000-45000 -> 50000"
        echo "Obfs: Salamander"
        echo "Obfs Password: ${HYSTERIA2_OBFS_PASSWORD}"
        echo "Up/Down: ${HYSTERIA2_UP_MBPS:-100}/${HYSTERIA2_DOWN_MBPS:-100} Mbps"
        echo ""
    fi

    echo "=============================================="
    echo "         SHARE LINKS"
    echo "=============================================="
    echo -e "$SHARE_LINKS"
    echo ""
    echo "=============================================="

    # Save share links to file
    echo -e "$SHARE_LINKS" > "${PERSIST_SHARE_LINKS}"
    ln -sf "${PERSIST_SHARE_LINKS}" /etc/sing-box/share_links.txt

    # Save complete deployment info to JSON file
    log_step "Saving deployment information..."
        cat > "${PERSIST_INFO}" <<EOFINFO
{
  "node_name": "${NODE_NAME}",
  "server_ipv4": "${PUBLIC_IPV4:-}",
  "server_ipv6": "${PUBLIC_IPV6:-}",
  "tls_domain": "${TLS_DOMAIN}",
  "custom_domain": "${CUSTOM_DOMAIN:-}",
  "uuid": "${UUID}",
  "deployed_at": "$(date -Iseconds)",
  "protocols": {
    "reality": {
      "enabled": ${ENABLE_REALITY:-0},
      "server_ipv4": "${PUBLIC_IPV4:-}",
      "server_ipv6": "${PUBLIC_IPV6:-}",
      "server_name": "${REALITY_SERVER_NAME}",
      "server_port": ${REALITY_SERVER_PORT:-443},
      "public_key": "${REALITY_PUBLIC_KEY}",
      "private_key": "${REALITY_PRIVATE_KEY}",
      "short_id": "${REALITY_SHORT_ID}",
      "ports": "${REALITY_PORT_LIST:-}"
    },
    "hysteria2": {
      "enabled": ${ENABLE_HYSTERIA2:-0},
      "server_ipv4": "${PUBLIC_IPV4:-}",
      "server_ipv6": "${PUBLIC_IPV6:-}",
      "sni": "${TLS_DOMAIN}",
      "up_mbps": ${HYSTERIA2_UP_MBPS:-100},
      "down_mbps": ${HYSTERIA2_DOWN_MBPS:-100},
      "obfs": "salamander",
      "obfs_password": "${HYSTERIA2_OBFS_PASSWORD}",
      "ports": "${HYSTERIA2_PORT_LIST:-}"
    }
  }
}
EOFINFO

    ln -sf "${PERSIST_INFO}" /etc/sing-box/deployment_info.json

    log_info "Deployment info saved to /etc/sing-box/deployment_info.json"
    log_info "Share links saved to /etc/sing-box/share_links.txt"

    # Start sing-box
    log_step "Starting sing-box..."
    exec sing-box run -c "${PERSIST_CONFIG}"
}

# Run main function
main "$@"
