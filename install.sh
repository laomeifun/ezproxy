#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[install] %s\n" "$*"
}

warn() {
  printf "[install][warn] %s\n" "$*" >&2
}

die() {
  printf "[install][error] %s\n" "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "请用 root 运行（例如：sudo bash install.sh）"
  fi
}

detect_distro() {
  if [[ ! -f /etc/os-release ]]; then
    die "无法检测系统类型（缺少 /etc/os-release），目前仅支持 Debian/Ubuntu"
  fi
  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu|debian)
      ;;
    *)
      die "当前系统 ID=${ID:-unknown} 不在支持范围（仅 Debian/Ubuntu）"
      ;;
  esac
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

trim() {
  local s="$1"
  # trim leading
  s="${s#${s%%[![:space:]]*}}"
  # trim trailing
  s="${s%${s##*[![:space:]]}}"
  printf "%s" "$s"
}

read_env_file_value() {
  local env_file="$1"
  local key="$2"
  [[ -f "$env_file" ]] || return 1
  # 支持 KEY=value（忽略注释与空行）
  local line
  line=$(grep -E "^\s*${key}=" "$env_file" 2>/dev/null | tail -n1 || true)
  [[ -n "$line" ]] || return 1
  printf "%s" "${line#*=}"
  return 0
}

read_compose_list_env_value() {
  local compose_file="$1"
  local key="$2"
  [[ -f "$compose_file" ]] || return 1
  # 解析形如：- KEY=value
  local val
  val=$(sed -nE "s/^\s*-\s*${key}=([^#]+).*$/\1/p" "$compose_file" | tail -n1 || true)
  val=$(trim "${val:-}")
  [[ -n "$val" ]] || return 1
  printf "%s" "$val"
  return 0
}

get_cfg() {
  # 优先级：脚本运行时环境变量 > .env > docker-compose.yaml > 默认值
  local key="$1"
  local default="$2"
  local project_dir="$3"
  local compose_file="$4"

  if [[ -n "${!key-}" ]]; then
    printf "%s" "${!key}"
    return 0
  fi

  local env_file="${project_dir}/.env"
  local v
  if v=$(read_env_file_value "$env_file" "$key" 2>/dev/null); then
    v=$(trim "$v")
    printf "%s" "$v"
    return 0
  fi

  if v=$(read_compose_list_env_value "$compose_file" "$key" 2>/dev/null); then
    printf "%s" "$v"
    return 0
  fi

  printf "%s" "$default"
}

apt_install() {
  local pkgs=("$@")
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "已检测到 docker，跳过安装"
    return 0
  fi

  log "安装 Docker Engine + Compose 插件..."
  apt-get update -y
  apt_install ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/"${ID}"/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local arch
  arch=$(dpkg --print-architecture)
  local codename
  codename=$(lsb_release -cs)

  cat >/etc/apt/sources.list.d/docker.list <<EOF
 deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${codename} stable
EOF

  apt-get update -y
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
  log "Docker 安装完成：$(docker --version 2>/dev/null || true)"
  log "Compose 插件：$(docker compose version 2>/dev/null || true)"
}

ensure_project_dirs() {
  local project_dir="$1"
  mkdir -p "${project_dir}/data/conf" "${project_dir}/data/tls"

  # 让宿主机查看/编辑更方便：若通过 sudo 运行，尽量归属给原用户
  if [[ -n "${SUDO_USER:-}" ]] && id "${SUDO_USER}" >/dev/null 2>&1; then
    chown -R "${SUDO_USER}":"${SUDO_USER}" "${project_dir}/data" || true
  fi
}

optimize_sysctl() {
  log "配置系统参数（UDP 缓冲区 + TCP BBR）..."
  cat >/etc/sysctl.d/99-ezproxy.conf <<'EOF'
# EZProxy Tuning
# UDP buffer (Hysteria2/TUIC)
net.core.rmem_max = 8000000
net.core.wmem_max = 8000000
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# TCP BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  sysctl --system >/dev/null
}

parse_ports_and_apply_ufw() {
  # $1 = ports string (e.g. "443", "443,8443", "20000-45000")
  # $2 = proto (tcp|udp)
  # $3 = description
  local ports_raw="$1"
  local proto="$2"
  local desc="$3"

  ports_raw=$(trim "${ports_raw:-}")
  [[ -n "$ports_raw" ]] || return 0

  IFS=',' read -r -a parts <<<"$ports_raw"
  for part in "${parts[@]}"; do
    part=$(trim "$part")
    [[ -n "$part" ]] || continue

    # range: 20000-45000
    if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
      local ufw_range="${part/-/:}"
      log "UFW 放行 ${desc}: ${ufw_range}/${proto}"
      ufw allow "${ufw_range}/${proto}" >/dev/null
      continue
    fi

    # single port
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      log "UFW 放行 ${desc}: ${part}/${proto}"
      ufw allow "${part}/${proto}" >/dev/null
      continue
    fi

    warn "无法识别端口格式 '${part}'（跳过）"
  done
}

configure_ufw() {
  local project_dir="$1"
  local compose_file="$2"

  log "安装并配置 UFW 防火墙规则..."
  apt-get update -y
  apt_install ufw

  local ssh_port
  ssh_port="${SSH_PORT:-22}"
  if [[ "$ssh_port" =~ ^[0-9]+$ ]]; then
    ufw allow "${ssh_port}/tcp" >/dev/null
    log "UFW 放行 SSH: ${ssh_port}/tcp"
  else
    warn "SSH_PORT='${ssh_port}' 非数字，将仅放行 OpenSSH profile"
  fi
  ufw allow OpenSSH >/dev/null || true

  local enable_reality
  enable_reality=$(get_cfg ENABLE_REALITY "1" "$project_dir" "$compose_file")
  local enable_hy2
  enable_hy2=$(get_cfg ENABLE_HYSTERIA2 "1" "$project_dir" "$compose_file")
  local reality_ports
  reality_ports=$(get_cfg REALITY_PORTS "443" "$project_dir" "$compose_file")
  local hy2_ports
  hy2_ports=$(get_cfg HYSTERIA2_PORTS "50000" "$project_dir" "$compose_file")
  local hy2_mport
  hy2_mport=$(get_cfg HYSTERIA2_MPORT_RANGE "" "$project_dir" "$compose_file")
  local le_mode
  le_mode=$(get_cfg LE_MODE "selfsigned" "$project_dir" "$compose_file")

  if [[ "$enable_reality" == "1" ]]; then
    parse_ports_and_apply_ufw "$reality_ports" tcp "Reality"
  else
    log "ENABLE_REALITY!=1，跳过 Reality 端口放行"
  fi

  if [[ "$enable_hy2" == "1" ]]; then
    parse_ports_and_apply_ufw "$hy2_ports" udp "Hysteria2"

    # mport range only matters when using main port 50000 in this repo's iptables logic
    hy2_mport=$(trim "${hy2_mport:-}")
    if [[ -n "$hy2_mport" ]] && [[ "$hy2_mport" != "0" ]] && [[ "$hy2_mport" != "disable" ]]; then
      parse_ports_and_apply_ufw "$hy2_mport" udp "Hysteria2 mport"
    else
      log "HYSTERIA2_MPORT_RANGE 未设置或已禁用，跳过 mport 范围放行"
    fi
  else
    log "ENABLE_HYSTERIA2!=1，跳过 Hysteria2 端口放行"
  fi

  # If user wants Let's Encrypt, open 80/tcp for HTTP-01 standalone
  if [[ "$le_mode" == "auto" || "$le_mode" == "letsencrypt" ]]; then
    log "检测到 LE_MODE=${le_mode}，放行 80/tcp 用于 Let's Encrypt HTTP-01"
    ufw allow 80/tcp >/dev/null
  fi

  ufw --force enable >/dev/null
  log "UFW 已启用"
}

install_fail2ban() {
  log "安装并启用 Fail2ban..."
  apt-get update -y
  apt_install fail2ban

  mkdir -p /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
# 采用发行版默认的后端/日志配置
bantime = 1h
findtime = 10m
maxretry = 5
EOF

  systemctl enable --now fail2ban
  log "Fail2ban 已启动：$(fail2ban-client ping 2>/dev/null || true)"
}

deploy_compose() {
  local project_dir="$1"
  cd "$project_dir"

  log "拉取镜像并启动服务..."
  docker compose pull
  docker compose up -d

  log "服务已启动，可查看链接：docker compose logs -f 或 docker compose exec ezproxy cat /etc/sing-box/share_links.txt"
}

show_links() {
  local project_dir="$1"
  cd "$project_dir"

  log "等待服务初始化并生成链接 (约需 5-10 秒)..."
  local retries=20
  while [[ $retries -gt 0 ]]; do
    if docker compose exec ezproxy test -f /etc/sing-box/share_links.txt >/dev/null 2>&1; then
      echo ""
      echo "=================================================================="
      echo "                      EZProxy 部署成功                            "
      echo "=================================================================="
      docker compose exec ezproxy cat /etc/sing-box/share_links.txt
      echo ""
      echo "=================================================================="
      return 0
    fi
    sleep 2
    ((retries--))
  done

  warn "未能在规定时间内获取到分享链接，请稍后手动执行："
  warn "cd $project_dir && docker compose exec ezproxy cat /etc/sing-box/share_links.txt"
}

main() {
  require_root
  detect_distro

  local project_dir
  project_dir=$(script_dir)
  local compose_file="${project_dir}/docker-compose.yaml"

  [[ -f "$compose_file" ]] || die "未找到 ${compose_file}，请在项目根目录运行该脚本"

  log "项目目录：${project_dir}"

  install_docker
  ensure_project_dirs "$project_dir"
  optimize_sysctl
  configure_ufw "$project_dir" "$compose_file"
  install_fail2ban
  deploy_compose "$project_dir"
  show_links "$project_dir"

  log "完成"
}

main "$@"
