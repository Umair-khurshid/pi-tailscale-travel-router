#!/usr/bin/bash
set -Eeuo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run this script with sudo." >&2; exit 1; }

systemctl disable --now hostapd dnsmasq 2>/dev/null || true
systemctl disable --now pi-travel-router-nftables.service 2>/dev/null || true
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.d/pi-travel-router.conf
rm -f /etc/systemd/network/30-pi-travel-router-*.network
rm -f /etc/sysctl.d/90-pi-travel-router.conf
rm -f /etc/nftables.d/pi-travel-router.nft
rm -f /etc/systemd/system/pi-travel-router-nftables.service
rm -f /etc/NetworkManager/conf.d/99-pi-travel-router-unmanaged.conf

systemctl restart NetworkManager 2>/dev/null || true
systemctl daemon-reload
systemctl restart systemd-networkd 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true

echo "Project configuration removed. Tailscale and /etc/pi-travel-router/router.env were left untouched."
