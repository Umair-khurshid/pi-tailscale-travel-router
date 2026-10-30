# Network topology and design notes

## Default design

The project uses Ethernet as the upstream connection and the Pi's Wi-Fi interface as the local access point. NetworkManager retains control of the WAN interface. `systemd-networkd` assigns the static address to the AP interface, `hostapd` provides Wi-Fi, and `dnsmasq` provides DHCP and DNS forwarding.

`nftables` adds a dedicated IPv4 NAT table for traffic sourced from the AP subnet. It does not flush or replace the host's existing ruleset.

## Wi-Fi WAN

A single Wi-Fi radio often cannot reliably operate as a station connected to a hotel AP and as an access point for your own clients at the same time. Some chipsets and drivers support concurrent virtual interfaces, but this is hardware- and driver-dependent.

For a Wi-Fi WAN, use a second Wi-Fi adapter for the upstream connection or an adapter explicitly verified to support concurrent `managed` and `AP` modes. Then configure the upstream interface with NetworkManager and set `WAN_IFACE` to that interface. Keep `AP_IFACE` on the separate AP-capable adapter.

## Tailscale routing

There are three distinct paths to keep in mind:

1. Local Wi-Fi clients reach the internet through the Pi's WAN interface using IPv4 NAT.
2. Devices in the tailnet reach the Pi and other tailnet devices through Tailscale.
3. Remote tailnet clients can optionally select the Pi as an exit node. In that case, their internet traffic is forwarded through the Pi's upstream connection.

A subnet router is different from an exit node. Use subnet routing when tailnet devices need to reach a separate private LAN behind the Pi. Use an exit node when remote tailnet devices should route general internet traffic through the Pi.

## Firewall caution

The supplied nftables file only adds NAT. It deliberately avoids a global `flush ruleset` and does not impose a global forward-chain policy, because doing so can break Tailscale, Docker, VPNs, or an existing firewall. Review and integrate forwarding policy with the firewall already installed on your system.
