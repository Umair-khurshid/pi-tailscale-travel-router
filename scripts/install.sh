#!/usr/bin/bash
set -Eeuo pipefail

CONFIG_FILE="/etc/pi-travel-router/router.env"
PROJECT_DIR="/etc/pi-travel-router"

log() { printf '[pi-travel-router] %s\n' "$*"; }
die() { printf '[pi-travel-router] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "Run this script with sudo."
[[ -r "$CONFIG_FILE" ]] || die "Missing $CONFIG_FILE. Copy config/router.env.example there and edit it first."

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${WAN_IFACE:?WAN_IFACE is required}"
: "${AP_IFACE:?AP_IFACE is required}"
: "${AP_ADDRESS:?AP_ADDRESS is required}"
: "${AP_CIDR:?AP_CIDR is required}"
: "${DHCP_START:?DHCP_START is required}"
: "${DHCP_END:?DHCP_END is required}"
: "${DHCP_LEASE:?DHCP_LEASE is required}"
: "${WIFI_SSID:?WIFI_SSID is required}"
: "${WIFI_PASSPHRASE:?WIFI_PASSPHRASE is required}"
: "${WIFI_COUNTRY:?WIFI_COUNTRY is required}"
: "${WIFI_CHANNEL:?WIFI_CHANNEL is required}"
: "${WIFI_HW_MODE:?WIFI_HW_MODE is required}"
: "${DNS_UPSTREAM:?DNS_UPSTREAM is required}"

[[ "$WIFI_PASSPHRASE" != "CHANGE-ME-TO-A-LONG-RANDOM-PASSWORD" ]] || die "Set WIFI_PASSPHRASE in $CONFIG_FILE before installing."
(( ${#WIFI_PASSPHRASE} >= 8 && ${#WIFI_PASSPHRASE} <= 63 )) || die "WIFI_PASSPHRASE must be 8 to 63 characters."
[[ "$WIFI_SSID" != *$'\n'* ]] || die "WIFI_SSID must be a single line."
[[ "$WAN_IFACE" != "$AP_IFACE" ]] || die "WAN_IFACE and AP_IFACE must be different."

ip link show "$WAN_IFACE" >/dev/null 2>&1 || die "WAN interface $WAN_IFACE does not exist."
ip link show "$AP_IFACE" >/dev/null 2>&1 || die "AP interface $AP_IFACE does not exist."

if ! grep -q 'VERSION_CODENAME=bookworm' /etc/os-release; then
  log "Warning: this project targets Raspberry Pi OS Bookworm. Review all generated configuration before proceeding."
fi

if ! command -v nmcli >/dev/null 2>&1; then
  die "NetworkManager was not detected. This installer targets Raspberry Pi OS Bookworm with NetworkManager."
fi

log "Installing packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y hostapd dnsmasq nftables

install -d -m 0750 "$PROJECT_DIR"

# Keep NetworkManager on the WAN interface, but let systemd-networkd own the AP interface.
install -d -m 0755 /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-pi-travel-router-unmanaged.conf <<EOF_NM
[keyfile]
unmanaged-devices=interface-name:${AP_IFACE}
EOF_NM

install -d -m 0755 /etc/systemd/network
cat > "/etc/systemd/network/30-pi-travel-router-${AP_IFACE}.network" <<EOF_NETWORK
[Match]
Name=${AP_IFACE}

[Network]
Address=${AP_ADDRESS}/${AP_CIDR}
ConfigureWithoutCarrier=yes
LinkLocalAddressing=no
IPv6AcceptRA=no
EOF_NETWORK

install -d -m 0755 /etc/hostapd
cat > /etc/hostapd/hostapd.conf <<EOF_HOSTAPD
country_code=${WIFI_COUNTRY}
interface=${AP_IFACE}
driver=nl80211
ssid=${WIFI_SSID}
hw_mode=${WIFI_HW_MODE}
channel=${WIFI_CHANNEL}
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=${WIFI_PASSPHRASE}
EOF_HOSTAPD

if grep -q '^#DAEMON_CONF=' /etc/default/hostapd 2>/dev/null; then
  sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
elif grep -q '^DAEMON_CONF=' /etc/default/hostapd 2>/dev/null; then
  sed -i 's|^DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
else
  printf '\nDAEMON_CONF="/etc/hostapd/hostapd.conf"\n' >> /etc/default/hostapd
fi

install -d -m 0755 /etc/dnsmasq.d
cat > /etc/dnsmasq.d/pi-travel-router.conf <<EOF_DNSMASQ
interface=${AP_IFACE}
bind-dynamic
no-resolv
server=${DNS_UPSTREAM}
dhcp-authoritative
dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,${DHCP_LEASE}
dhcp-option=option:router,${AP_ADDRESS}
dhcp-option=option:dns-server,${AP_ADDRESS}
EOF_DNSMASQ

cat > /etc/sysctl.d/90-pi-travel-router.conf <<'EOF_SYSCTL'
net.ipv4.ip_forward=1
EOF_SYSCTL
sysctl --system >/dev/null

# Add a dedicated NAT table. Do not flush the host's complete nftables ruleset.
install -d -m 0755 /etc/nftables.d
cat > /etc/nftables.d/pi-travel-router.nft <<EOF_NFT
table ip pi_travel_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${WAN_IFACE}" ip saddr ${AP_ADDRESS}/${AP_CIDR} masquerade
    }
}
EOF_NFT

cat > /etc/systemd/system/pi-travel-router-nftables.service <<'EOF_SERVICE'
[Unit]
Description=IPv4 NAT for Raspberry Pi travel router
Wants=network-online.target
After=network-online.target nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/sbin/nft delete table ip pi_travel_nat
ExecStart=/usr/sbin/nft -f /etc/nftables.d/pi-travel-router.nft
ExecStop=-/usr/sbin/nft delete table ip pi_travel_nat

[Install]
WantedBy=multi-user.target
EOF_SERVICE

log "Reloading network and router services..."
systemctl restart NetworkManager
systemctl enable --now systemd-networkd
systemctl restart systemd-networkd
systemctl unmask hostapd
systemctl enable --now hostapd
systemctl enable --now dnsmasq
systemctl daemon-reload
systemctl enable --now pi-travel-router-nftables.service

log "Installation finished. Check service status and connect a client to ${WIFI_SSID}."
log "WAN: ${WAN_IFACE}; AP: ${AP_IFACE}; AP gateway: ${AP_ADDRESS}/${AP_CIDR}"
