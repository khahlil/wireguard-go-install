# WireGuard-Go Installer

Automated Bash script to quickly install, configure, and manage a [WireGuard-Go](https://github.com/WireGuard/wireguard-go) VPN server on Linux containers (OpenVZ/LXC/venet0).

Designed for low-overhead setups with built-in NAT routing and automated system-wide DNS management.

---

## Supported OS

* **Debian 12 (Bookworm)** *(Tested and fully supported)*

---

## Installation & Usage

Run the commands below as the **root** user. Follow the interactive prompts to complete the setup.

```bash
curl -O https://raw.githubusercontent.com/khahlil/wireguard-go-install/main/wireguard-go-install.sh
chmod +x wireguard-go-install.sh
./wireguard-go-install.sh
```
---
## Key Features

* OpenVZ / LXC Friendly: Uses wireguard-go userspace implementation to work seamlessly on virtual environments without requiring native kernel modules.

* Auto NAT Routing: Automatically configures iptables and IPv4 forwarding so clients browse using the server's public IP.

* Centralized DNS: Sets the upstream DNS choice directly on the server for all connected VPN peers.

* Interactive Management: Re-run the script anytime to add new clients, revoke existing ones, or completely uninstall WireGuard.

* QR Code Support: Generates ANSI terminal QR codes instantly for fast mobile device onboarding.
