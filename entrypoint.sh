#!/bin/bash
set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_step() { echo -e "\033[0;34m[STEP]\033[0m $1"; }

PERSIST_DIR="/etc/sing-box/conf"; PERSIST_CONFIG="${PERSIST_DIR}/config.json"; PERSIST_SHARE_LINKS="${PERSIST_DIR}/share_links.txt"

generate_uuid() { if command -v sing-box &>/dev/null; then sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid; else cat /proc/sys/kernel/random/uuid; fi; }
generate_reality_keypair() { local r; r=$(sing-box generate reality-keypair 2>/dev/null); echo "$r"; }
urlencode() { local s="$1"; local len=${#s}; local e=""; for (( i=0 ; i<len ; i++ )); do c=${s:$i:1}; case "$c" in [-_.~a-zA-Z0-9] ) o="$c" ;; * ) printf -v o '%%%02X' "'$c" ;; esac; e+="$o"; done; echo "$e"; }

obtain_certificate() {
    local d="$1"; local cdir="/etc/sing-box/tls"; local cp="${cdir}/${d}.crt"; local kp="${cdir}/${d}.key"
    mkdir -p "$cdir"
    if [[ "${LE_MODE:-auto}" != "selfsigned" ]]; then
        if certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email --domain "$d" --preferred-challenges http --http-01-port 80 2>&1; then
            cp -f "/etc/letsencrypt/live/$d/fullchain.pem" "$cp"; cp -f "/etc/letsencrypt/live/$d/privkey.pem" "$kp"; return 0
        fi
    fi
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout "$kp" -out "$cp" -days 365 -nodes -subj "/CN=$d" -addext "subjectAltName=DNS:$d" 2>/dev/null
}

main() {
    log_step "Starting..."; mkdir -p "$PERSIST_DIR"
    if [[ "${REUSE_CONFIG:-1}" != "0" && -f "$PERSIST_CONFIG" ]]; then
        if sing-box check -c "$PERSIST_CONFIG" 2>/dev/null; then ln -sf "$PERSIST_CONFIG" /etc/sing-box/config.json; log_info "Reusing config"; exec sing-box run -c "$PERSIST_CONFIG"; fi
    fi
    v4=$(curl -4 -s --connect-timeout 5 http://ifconfig.me 2>/dev/null || echo ""); ip="${v4:-}"
    dom="${CUSTOM_DOMAIN:-${ip//./-}.sslip.io}"; UUID="${UUID:-$(generate_uuid)}"; NODE_NAME="${NODE_NAME:-$(hostname)}"; NODE_NAME="${NODE_NAME%%.*}"; inb=""; links=""

    if [[ "${ENABLE_REALITY:-1}" == "1" ]]; then
        rk=$(generate_reality_keypair); priv=$(echo "$rk"|grep "PrivateKey"|awk '{print $2}'); pub=$(echo "$rk"|grep "PublicKey"|awk '{print $2}'); sid=$(openssl rand -hex 8); sni="${REALITY_SERVER_NAME:-www.microsoft.com}"
        inb+="{\"type\":\"vless\",\"listen\":\"::\",\"listen_port\":443,\"tag\":\"rel-443\",\"users\":[{\"uuid\":\"$UUID\",\"flow\":\"xtls-rprx-vision\",\"name\":\"user\"}],\"tls\":{\"enabled\":true,\"server_name\":\"$sni\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"$sni\",\"server_port\":443},\"private_key\":\"$priv\",\"short_id\":[\"\",\"$sid\"]}}},"
        links+="vless://$(urlencode $UUID)@$v4:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$pub&sid=$sid&type=tcp#$(urlencode ${NODE_NAME}-Rel)\n"
    fi

    if [[ "${ENABLE_HYSTERIA2:-1}" == "1" || "${ENABLE_TUIC:-0}" == "1" ]]; then obtain_certificate "$dom"; fi
    if [[ "${ENABLE_HYSTERIA2:-1}" == "1" ]]; then
        pass=$(openssl rand -hex 16)
        inb+="{\"type\":\"hysteria2\",\"listen\":\"::\",\"listen_port\":50000,\"tag\":\"hy2-50000\",\"users\":[{\"password\":\"$UUID\",\"name\":\"user\"}],\"up_mbps\":180,\"down_mbps\":180,\"obfs\":{\"type\":\"salamander\",\"password\":\"$pass\"},\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"/etc/sing-box/tls/$dom.crt\",\"key_path\":\"/etc/sing-box/tls/$dom.key\"}},"
        links+="hysteria2://$(urlencode $UUID)@$v4:50000?sni=$dom&alpn=h3&insecure=1&obfs=salamander&obfs-password=$pass#$(urlencode ${NODE_NAME}-Hy2)\n"
    fi
    if [[ "${ENABLE_TUIC:-0}" == "1" ]]; then
        inb+="{\"type\":\"tuic\",\"listen\":\"::\",\"listen_port\":50001,\"tag\":\"tuic-50001\",\"users\":[{\"uuid\":\"$UUID\",\"password\":\"$UUID\",\"name\":\"user\"}],\"congestion_control\":\"bbr\",\"zero_rtt_handshake\":true,\"heartbeat\":\"10s\",\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"/etc/sing-box/tls/$dom.crt\",\"key_path\":\"/etc/sing-box/tls/$dom.key\"}},"
        links+="tuic://$(urlencode $UUID):$(urlencode $UUID)@$v4:50001?sni=$dom&alpn=h3&congestion_control=bbr&udp_relay_mode=native&insecure=1#$(urlencode ${NODE_NAME}-Tuic)\n"
    fi

    cat > "$PERSIST_CONFIG" <<EOF
{"log":{"level":"info"},"inbounds":[${inb%,}],"outbounds":[{"type":"direct","tag":"direct-out"},{"type":"dns","tag":"dns-out"},{"type":"block","tag":"block"}],"route":{"rules":[{"geosite":["category-ads-all"],"outbound":"block"},{"protocol":"dns","outbound":"dns-out"}],"final":"direct-out"}}
EOF
    cat > "${PERSIST_DIR}/client_config.json" <<EOF
{"log":{"level":"info"},"dns":{"servers":[{"tag":"google","address":"tls://8.8.8.8"},{"tag":"local","address":"223.5.5.5","detour":"direct"}],"rules":[{"outbound":"any","server":"local"}]},"inbounds":[{"type":"mixed","listen":"127.0.0.1","listen_port":2080,"sniff":true}],"outbounds":[{"type":"direct","tag":"direct"},{"type":"block","tag":"block"},{"type":"dns","tag":"dns-out"}],"route":{"rules":[{"protocol":"dns","outbound":"dns-out"},{"geosite":"category-ads-all","outbound":"block"}],"final":"direct"}}
EOF
    echo -e "$links" > "$PERSIST_SHARE_LINKS"; ln -sf "$PERSIST_SHARE_LINKS" /etc/sing-box/share_links.txt
    log_info "Complete. Links:\n$links"; exec sing-box run -c "$PERSIST_CONFIG"
}
main "$@"
