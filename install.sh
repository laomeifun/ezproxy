#!/usr/bin/env bash
set -euo pipefail
log() { printf "[install] %s\n" "$*"; }
main() {
  d=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  mkdir -p "$d/data/conf" "$d/data/tls"
  apt-get update -y && apt-get install -y ufw docker.io docker-compose || true
  ufw allow 22/tcp; ufw allow 443/tcp; ufw allow 50000/udp; ufw allow 50001/udp; ufw --force enable || true
  cd "$d"; docker-compose up -d; log "Done."
}
main "$@"
