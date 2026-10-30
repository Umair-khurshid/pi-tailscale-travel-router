#!/usr/bin/bash
set -Eeuo pipefail

log() { printf '[pi-travel-router] %s\n' "$*"; }
die() { printf '[pi-travel-router] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "Run this script with sudo."
command -v tailscale >/dev/null 2>&1 || die "Tailscale is not installed. Install and authenticate it first."

install -m 0644 /dev/stdin /etc/sysctl.d/99-tailscale-exit-node.conf <<'EOF_SYSCTL'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF_SYSCTL
sysctl --system >/dev/null

tailscale set --advertise-exit-node
log "Exit-node advertisement enabled. Approve the default route on your Tailscale or Headscale control plane."
