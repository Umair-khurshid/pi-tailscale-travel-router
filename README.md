# Raspberry Pi Tailscale travel router

Turn a Raspberry Pi into a small Wi-Fi travel router with a private Tailscale connection and optional Headscale control server. The project configures a wireless access point, DHCP, IPv4 forwarding, and NAT. It also includes a separate, opt-in helper for advertising the Pi as a Tailscale exit node.

> **Status:** Community project starter. Review the configuration for your hardware and network before running it. It is not a one-click installer for every Raspberry Pi OS release or wireless chipset.

## What this project builds

The default layout is deliberately simple:

- `eth0` is the upstream/WAN interface and obtains its address from the upstream network.
- `wlan0` is the private Wi-Fi access point provided by the Pi.
- Wi-Fi clients receive addresses from `dnsmasq` and use the Pi as their gateway.
- `nftables` masquerades Wi-Fi client traffic out through the WAN interface using a dedicated systemd unit.
- Tailscale connects the Pi to your tailnet. You can use a hosted Tailscale control plane or your own Headscale server.
- The Pi can optionally advertise itself as an exit node for other tailnet devices.

This default topology does **not** automatically turn a hotel Wi-Fi connection into the WAN. If you want Wi-Fi uplink and Wi-Fi access point at the same time, you need a second wireless adapter and a chipset/driver combination that supports the required concurrent station and AP modes. Configure that separately and verify it with `iw list`.

## Features

- WPA2-Personal Wi-Fi access point using `hostapd`.
- DHCP and DNS forwarding for Wi-Fi clients using `dnsmasq`.
- IPv4 forwarding and NAT using `nftables`.
- A dedicated `systemd-networkd` profile for the AP interface.
- Tailscale client setup with optional Headscale login server.
- Optional exit-node advertisement and Headscale route approval instructions.
- Configuration kept outside the repository in `/etc/pi-travel-router/router.env`.
- Uninstall helper that removes this project's files and restores NetworkManager's management of the AP interface.

## Supported baseline

The scripts target **Raspberry Pi OS Bookworm (64-bit) with NetworkManager**, systemd, and a Raspberry Pi with a Wi-Fi interface capable of AP mode. Other Debian-derived systems may work, but are not tested by this project.

The default configuration assumes:

| Purpose | Interface / network |
|---|---|
| Upstream WAN | `eth0` |
| Wi-Fi access point | `wlan0` |
| AP gateway | `192.168.50.1/24` |
| DHCP pool | `192.168.50.20` to `192.168.50.200` |
| Wi-Fi country | `PK` (change if you are elsewhere) |
| Wi-Fi band | 2.4 GHz |

Check your actual interface names before installation:

```bash
ip -br link
 iw list
```

In `iw list`, look for `Supported interface modes` and confirm that `AP` is listed.

## Network and security notes

1. **Use a strong Wi-Fi passphrase.** The example file contains a placeholder and the installer refuses passwords shorter than eight characters. Do not commit your real `router.env` file.
2. **Do not expose the administration interface.** Keep SSH restricted to trusted networks or your tailnet.
3. **Captive portals still apply.** You may need to authenticate the Pi itself to a hotel or guest network before it can provide internet to clients.
4. **This is an IPv4 NAT baseline.** IPv6 forwarding and IPv6 firewall policy are not configured here. Clients may use IPv6 only if you separately design and test it.
5. **Firewall integration matters.** The project loads its own nftables table through a dedicated systemd unit and does not flush the host's ruleset. If you already use UFW, firewalld, Docker, or custom nftables rules, review the interaction before enabling forwarding.
6. **Tailscale and Headscale are separate pieces.** Tailscale is the client and data-plane software. Headscale is an optional self-hosted control server. You do not need Headscale to use this project.
7. **Exit node and Wi-Fi gateway are different functions.** The AP/NAT setup shares the Pi's upstream connection with local Wi-Fi clients. Exit-node advertisement lets remote tailnet devices route their internet traffic through the Pi. Enabling one does not automatically configure the other.

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/Umair-khurshid/pi-tailscale-travel-router.git
cd pi-tailscale-travel-router
```

### 2. Review and edit the configuration

Copy the example configuration:

```bash
sudo install -d -m 0750 /etc/pi-travel-router
sudo install -m 0600 config/router.env.example /etc/pi-travel-router/router.env
sudoedit /etc/pi-travel-router/router.env
```

At minimum, set a unique SSID and a strong Wi-Fi passphrase. Confirm `WAN_IFACE`, `AP_IFACE`, and `WIFI_COUNTRY` match your hardware and location.

### 3. Run the installer

```bash
sudo ./scripts/install.sh
```

The installer checks the operating system, required settings, and interface names. It installs the required packages, marks the AP interface unmanaged by NetworkManager, assigns the AP address with `systemd-networkd`, writes the `hostapd`, `dnsmasq`, `nftables`, and sysctl configuration, and enables the services.

The installer does not change the WAN interface configuration. NetworkManager continues to manage the Ethernet uplink.

### 4. Connect a client

Connect a phone or laptop to the configured SSID. It should receive an address in `192.168.50.0/24`, use `192.168.50.1` as its gateway, and reach the internet through the Pi's Ethernet uplink.

Useful checks on the Pi:

```bash
ip -br address
ip route
systemctl status hostapd dnsmasq systemd-networkd pi-travel-router-nftables
sudo nft list ruleset
journalctl -u hostapd -u dnsmasq --since today
```

## Configure Tailscale and Headscale

Install Tailscale using the official instructions for Raspberry Pi OS:

<https://tailscale.com/download/linux>

For a hosted Tailscale tailnet, authenticate normally:

```bash
sudo tailscale up
```

For a self-hosted Headscale control server, use your own HTTPS URL:

```bash
sudo tailscale up --login-server https://headscale.example.net
```

Replace the example hostname with your Headscale URL. Do not put authentication keys or private credentials in this repository.

### Advertise the Pi as an exit node (optional)

Enable IP forwarding and advertise the node:

```bash
sudo ./scripts/enable-exit-node.sh
```

For Headscale, approve the advertised default route on the Headscale server. On current Headscale releases, first inspect the routes:

```bash
headscale nodes list-routes
```

Then approve the IPv4 default route for the appropriate node identifier:

```bash
headscale nodes approve-routes --identifier NODE_ID --routes 0.0.0.0/0
```

Use the command syntax documented for the Headscale version you run. See <https://headscale.net/stable/ref/routes/>.

On a client device, select the Pi as its exit node. On Linux, for example:

```bash
sudo tailscale set --exit-node=<PI-TAILSCALE-IP>
```

To stop using it:

```bash
sudo tailscale set --exit-node=
```

See the official Tailscale exit-node documentation: <https://tailscale.com/docs/features/exit-nodes>.

## Configuration reference

All project-specific settings live in `/etc/pi-travel-router/router.env`.

| Variable | Default | Meaning |
|---|---|---|
| `WAN_IFACE` | `eth0` | Interface connected to upstream internet |
| `AP_IFACE` | `wlan0` | Interface broadcasting the Wi-Fi network |
| `AP_ADDRESS` | `192.168.50.1` | Static IPv4 address for the AP |
| `AP_CIDR` | `24` | Prefix length for the AP network |
| `DHCP_START` | `192.168.50.20` | First DHCP address |
| `DHCP_END` | `192.168.50.200` | Last DHCP address |
| `DHCP_LEASE` | `12h` | DHCP lease duration |
| `WIFI_SSID` | `Pi-Travel` | Wireless network name |
| `WIFI_PASSPHRASE` | placeholder | WPA2 passphrase, 8 to 63 characters |
| `WIFI_COUNTRY` | `PK` | Two-letter regulatory country code |
| `WIFI_CHANNEL` | `6` | 2.4 GHz channel |
| `WIFI_HW_MODE` | `g` | `g` for 2.4 GHz; use other modes only after checking hardware support |
| `DNS_UPSTREAM` | `1.1.1.1` | Upstream DNS resolver used by dnsmasq |

The AP subnet must not overlap with the upstream network or any networks you route through Tailscale.

## Troubleshooting

### The SSID does not appear

- Confirm the adapter supports AP mode with `iw list`.
- Check the regulatory domain and channel restrictions.
- Inspect `journalctl -u hostapd -b`.
- Confirm NetworkManager is not managing the AP interface: `nmcli device status`.

### Clients connect but do not receive an IP address

- Check `systemctl status dnsmasq`.
- Inspect `journalctl -u dnsmasq -b`.
- Confirm the AP interface has the configured static address: `ip address show wlan0`.

### Clients receive an IP address but cannot reach the internet

- Confirm the Pi itself can reach the internet through the WAN interface.
- Confirm IPv4 forwarding: `sysctl net.ipv4.ip_forward`.
- Check the NAT table: `sudo nft list table ip pi_travel_nat`.
- Confirm `WAN_IFACE` is the actual upstream interface.
- Review any existing firewall rules. UFW, firewalld, Docker, and custom nftables policies can affect forwarding.

### Tailscale exit-node traffic does not work

- Confirm the Pi advertises the exit node: `tailscale status`.
- Confirm Headscale has approved `0.0.0.0/0` if you use Headscale.
- Check that the client has selected the Pi as its exit node.
- Review the Tailscale and Headscale documentation for ACL/grant and route-approval requirements.

## Uninstall

Run:

```bash
sudo ./scripts/uninstall.sh
```

The script stops and disables this project's services, removes its configuration files, and removes the NetworkManager unmanaged-device rule created by the installer. It then re-enables NetworkManager management of the AP interface. It does not uninstall Tailscale or Headscale, remove unrelated firewall rules, or delete the repository.


## Contributing

Issues and pull requests are welcome. Include your Raspberry Pi model, Raspberry Pi OS release, wireless adapter chipset, and relevant service logs when reporting a problem. Remove public IP addresses, Wi-Fi credentials, Tailscale auth keys, and other secrets before posting logs.

