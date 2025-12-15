#!/bin/bash
#
# Quick deployment script for sing-box auto-deploy container
# Usage: ./deploy.sh [options]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║        Sing-Box Auto-Deploy Container                     ║"
    echo "║  Supports: VLESS-Reality, AnyTLS, Hysteria2, TUIC V5      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  up        Start the container (default)"
    echo "  down      Stop and remove the container"
    echo "  restart   Restart the container"
    echo "  logs      Show container logs"
    echo "  status    Show container status"
    echo "  links     Show share links"
    echo "  config    Show current configuration"
    echo "  build     Build the container image"
    echo "  clean     Remove container, images and data"
    echo ""
    echo "Options:"
    echo "  --uuid UUID           Set custom UUID"
    echo "  --domain DOMAIN       Set custom domain for TLS (instead of sslip.io)"
    echo "  --reality-port PORT   Set Reality port(s), comma-separated"
    echo "  --anytls-port PORT    Set AnyTLS port(s), comma-separated"
    echo "  --hy2-port PORT       Set Hysteria2 port(s), comma-separated"
    echo "  --tuic-port PORT      Set TUIC port(s), comma-separated"
    echo "  --no-reality          Disable VLESS-Reality"
    echo "  --no-anytls           Disable AnyTLS"
    echo "  --no-hy2              Disable Hysteria2"
    echo "  --no-tuic             Disable TUIC"
    echo "  --only-reality        Enable only Reality"
    echo "  --only-hy2            Enable only Hysteria2"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 up                                  # Start with all defaults (random ports)"
    echo "  $0 up --uuid my-custom-uuid            # Start with custom UUID"
    echo "  $0 up --domain proxy.example.com       # Use custom domain for TLS"
    echo "  $0 up --reality-port 443 --hy2-port 8443"
    echo "  $0 up --only-reality --reality-port 443,444,445"
    echo "  $0 logs -f                             # Follow logs"
    echo ""
}

# Default values
COMMAND="up"
UUID=""
CUSTOM_DOMAIN=""
REALITY_PORTS=""
ANYTLS_PORTS=""
HYSTERIA2_PORTS=""
TUIC_PORTS=""
ENABLE_REALITY="1"
ENABLE_ANYTLS="1"
ENABLE_HYSTERIA2="1"
ENABLE_TUIC="1"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        up|down|restart|logs|status|links|config|build|clean)
            COMMAND="$1"
            shift
            ;;
        --uuid)
            UUID="$2"
            shift 2
            ;;
        --domain)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        --reality-port)
            REALITY_PORTS="$2"
            shift 2
            ;;
        --anytls-port)
            ANYTLS_PORTS="$2"
            shift 2
            ;;
        --hy2-port)
            HYSTERIA2_PORTS="$2"
            shift 2
            ;;
        --tuic-port)
            TUIC_PORTS="$2"
            shift 2
            ;;
        --no-reality)
            ENABLE_REALITY="0"
            shift
            ;;
        --no-anytls)
            ENABLE_ANYTLS="0"
            shift
            ;;
        --no-hy2)
            ENABLE_HYSTERIA2="0"
            shift
            ;;
        --no-tuic)
            ENABLE_TUIC="0"
            shift
            ;;
        --only-reality)
            ENABLE_REALITY="1"
            ENABLE_ANYTLS="0"
            ENABLE_HYSTERIA2="0"
            ENABLE_TUIC="0"
            shift
            ;;
        --only-hy2)
            ENABLE_REALITY="0"
            ENABLE_ANYTLS="0"
            ENABLE_HYSTERIA2="1"
            ENABLE_TUIC="0"
            shift
            ;;
        -h|--help)
            print_banner
            usage
            exit 0
            ;;
        -f)
            # Pass through for logs command
            LOGS_FOLLOW="-f"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Create data directories
ensure_directories() {
    mkdir -p "$SCRIPT_DIR/data/tls"
    mkdir -p "$SCRIPT_DIR/data/config"
    mkdir -p "$SCRIPT_DIR/data/letsencrypt"
}

# Generate environment file
generate_env() {
    cat > "$SCRIPT_DIR/.env" <<EOF
# Auto-generated environment file
ENABLE_REALITY=${ENABLE_REALITY}
ENABLE_ANYTLS=${ENABLE_ANYTLS}
ENABLE_HYSTERIA2=${ENABLE_HYSTERIA2}
ENABLE_TUIC=${ENABLE_TUIC}
REALITY_PORTS=${REALITY_PORTS}
ANYTLS_PORTS=${ANYTLS_PORTS}
HYSTERIA2_PORTS=${HYSTERIA2_PORTS}
TUIC_PORTS=${TUIC_PORTS}
UUID=${UUID}
CUSTOM_DOMAIN=${CUSTOM_DOMAIN}
REALITY_SERVER_NAME=
REALITY_SERVER_PORT=443
HYSTERIA2_UP_MBPS=100
HYSTERIA2_DOWN_MBPS=100
TUIC_CONGESTION=bbr
TZ=UTC
EOF
    echo -e "${GREEN}Environment file generated${NC}"
}

# Check if docker and docker-compose are available
check_requirements() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed${NC}"
        exit 1
    fi

    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        echo -e "${RED}Error: Docker Compose is not installed${NC}"
        exit 1
    fi
}

# Execute command
execute_command() {
    case $COMMAND in
        up)
            print_banner
            echo -e "${GREEN}Starting sing-box container...${NC}"
            ensure_directories
            generate_env
            $COMPOSE_CMD up -d --build
            echo ""
            echo -e "${GREEN}Container started!${NC}"
            echo -e "${YELLOW}Use '$0 logs -f' to view logs and share links${NC}"
            ;;
        down)
            echo -e "${YELLOW}Stopping sing-box container...${NC}"
            $COMPOSE_CMD down
            echo -e "${GREEN}Container stopped${NC}"
            ;;
        restart)
            echo -e "${YELLOW}Restarting sing-box container...${NC}"
            $COMPOSE_CMD restart
            echo -e "${GREEN}Container restarted${NC}"
            ;;
        logs)
            $COMPOSE_CMD logs $LOGS_FOLLOW sing-box
            ;;
        status)
            $COMPOSE_CMD ps
            ;;
        links)
            if [[ -f "$SCRIPT_DIR/data/config/../share_links.txt" ]] || docker exec sing-box-auto cat /etc/sing-box/share_links.txt 2>/dev/null; then
                :
            else
                echo -e "${YELLOW}Share links not yet generated. Container might still be starting...${NC}"
                echo -e "${YELLOW}Use '$0 logs' to check status${NC}"
            fi
            ;;
        config)
            docker exec sing-box-auto cat /etc/sing-box/config.json 2>/dev/null | jq . 2>/dev/null || \
            docker exec sing-box-auto cat /etc/sing-box/config.json 2>/dev/null || \
            echo -e "${YELLOW}Config not available. Is the container running?${NC}"
            ;;
        build)
            echo -e "${GREEN}Building sing-box image...${NC}"
            $COMPOSE_CMD build --no-cache
            echo -e "${GREEN}Build complete${NC}"
            ;;
        clean)
            echo -e "${RED}Warning: This will remove all data including certificates!${NC}"
            read -p "Are you sure? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                $COMPOSE_CMD down --rmi all -v 2>/dev/null || true
                rm -rf "$SCRIPT_DIR/data"
                rm -f "$SCRIPT_DIR/.env"
                echo -e "${GREEN}Cleaned up${NC}"
            else
                echo "Cancelled"
            fi
            ;;
    esac
}

# Main
check_requirements
execute_command
