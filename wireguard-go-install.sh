#!/bin/bash

# Secure WireGuard server installer
# Using wireguard-go from Debian 12 official repositories & support OpenVZ/venet0.

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		echo "This script must be run as root."
		exit 1
	fi
}

function checkVirt() {
	TUN_DEV="/dev/net/tun"
	if [ ! -c "$TUN_DEV" ]; then
		echo -e "${RED}TUN device ($TUN_DEV) is not available!${NC}"
		echo "Please enable the TUN/TAP feature on your VPS/Server control panel."
		exit 1
	fi
}

function checkOS() {
	if [ -f /etc/os-release ]; then
		source /etc/os-release
		if [ "$ID" != "debian" ]; then
			echo -e "${RED}This modified script is tailored specifically for Debian 12 (Bookworm).${NC}"
			exit 1
		fi
		if [ "$VERSION_ID" -lt 12 ]; then
			echo -e "${RED}Your Debian version ($VERSION_ID) is not supported. Please use Debian 12 or newer.${NC}"
			exit 1
		fi
	else
		echo -e "${RED}Could not detect operating system.${NC}"
		exit 1
	fi
}

function initialCheck() {
	isRoot
	checkVirt
	checkOS
}

function installQuestions() {
	# Clear screen untuk tampilan bersih (opsional)
	clear

	# Sleek Minimalist Header
	echo -e "${CYAN}=====================================================${NC}"
	echo -e "   ${BOLD}${GREEN}WireGuard Installer${NC} ${CYAN}(wireguard-go)${NC} - ${BOLD}Debian 12${NC}"
	echo -e "${CYAN}=====================================================${NC}"
	echo -e "${ORANGE}Answer the following questions to set up your server.${NC}\n"

	# 1. Detect Main Interface
	SERVER_NIC=$(ip route show default | grep -oP 'dev \K\S+' | head -n1)
	if [[ "$SERVER_NIC" == "link" ]] || [[ -z "$SERVER_NIC" ]]; then
		if ip link show venet0 &>/dev/null; then
			SERVER_NIC="venet0"
		fi
	fi
	
	# 2. Detect Public IP
	SERVER_PUB_IP=$(ip -4 addr show "$SERVER_NIC" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -n1)
	if [[ -z "$SERVER_PUB_IP" ]]; then
		SERVER_PUB_IP=$(curl -s4 --connect-timeout 5 https://ifconfig.me || curl -s4 --connect-timeout 5 https://api.ipify.org)
	fi

	# Network Settings Prompts
	echo -e "${BOLD}${YELLOW}[ Network Configuration ]${NC}"
	read -rp "$(echo -e "${CYAN}•${NC} Server Public IPv4   : ")" -e -i "$SERVER_PUB_IP" SERVER_PUB_IP
	read -rp "$(echo -e "${CYAN}•${NC} Network Interface    : ")" -e -i "$SERVER_NIC" SERVER_NIC
	read -rp "$(echo -e "${CYAN}•${NC} WireGuard Interface  : ")" -e -i "wg0" SERVER_WG_NIC
	read -rp "$(echo -e "${CYAN}•${NC} WireGuard Server IP  : ")" -e -i "10.66.66.1" SERVER_WG_IPV4

	# Port Selection
	echo -e "\n${BOLD}${YELLOW}[ Port Selection ]${NC}"
	echo -e "  ${GREEN}1)${NC} Default Port  ${CYAN}(51820)${NC}"
	echo -e "  ${GREEN}2)${NC} Random Port   ${CYAN}(1024-65535)${NC}"
	echo -e "  ${GREEN}3)${NC} Custom Port   ${CYAN}(Manual Input)${NC}"
	read -rp "$(echo -e "${CYAN}Select option [1-3]: ${NC}")" -e -i "1" PORT_CHOICE

	case "$PORT_CHOICE" in
		1)
			SERVER_PORT="51820"
			;;
		2)
			RANDOM_PORT=$(shuf -i 1024-65535 -n 1)
			while ss -ludn | grep -q ":$RANDOM_PORT "; do
				RANDOM_PORT=$(shuf -i 1024-65535 -n 1)
			done
			SERVER_PORT="$RANDOM_PORT"
			echo -e "  ${GREEN}✓${NC} Selected Random Port: ${BOLD}${GREEN}${SERVER_PORT}${NC}"
			;;
		3)
			read -rp "$(echo -e "  ${CYAN}• Enter Port [1024-65535]: ${NC}")" -e SERVER_PORT
			;;
		*)
			SERVER_PORT="51820"
			;;
	esac

	# DNS Options
	echo -e "\n${BOLD}${YELLOW}[ Client DNS Resolver ]${NC}"
	echo -e "  ${GREEN}1)${NC} Cloudflare ${CYAN}(1.1.1.1)${NC}"
	echo -e "  ${GREEN}2)${NC} Google     ${CYAN}(8.8.8.8)${NC}"
	echo -e "  ${GREEN}3)${NC} Quad9      ${CYAN}(9.9.9.9)${NC}"
	echo -e "  ${GREEN}4)${NC} AdGuard    ${CYAN}(94.140.14.14)${NC}"
	echo -e "  ${GREEN}5)${NC} OpenDNS    ${CYAN}(208.67.222.222)${NC}"
	echo -e "  ${GREEN}6)${NC} NextDNS    ${CYAN}(45.90.28.0)${NC}"
	echo -e "  ${GREEN}7)${NC} Custom IPv4 DNS"
	read -rp "$(echo -e "${CYAN}Select option [1-7]: ${NC}")" -e -i "1" DNS_CHOICE

	case "$DNS_CHOICE" in
		1) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
		2) CLIENT_DNS="8.8.8.8, 8.8.4.4" ;;
		3) CLIENT_DNS="9.9.9.9, 149.112.112.112" ;;
		4) CLIENT_DNS="94.140.14.14, 94.140.15.15" ;;
		5) CLIENT_DNS="208.67.222.222, 208.67.220.220" ;;
		6) CLIENT_DNS="45.90.28.0, 45.90.30.0" ;;
		7) 
			read -rp "$(echo -e "  ${CYAN}• Primary DNS: ${NC}")" CUSTOM_DNS1
			read -rp "$(echo -e "  ${CYAN}• Secondary DNS: ${NC}")" CUSTOM_DNS2
			CLIENT_DNS="${CUSTOM_DNS1}, ${CUSTOM_DNS2}"
			;;
		*) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
	esac

	# Client Isolation
	echo -e "\n${BOLD}${YELLOW}[ Client Isolation Settings ]${NC}"
	echo -e "  ${GREEN}1)${NC} Enabled  - Keeps clients separated for security ${GREEN}(Default)${NC}"
	echo -e "  ${GREEN}2)${NC} Disabled - Allows clients to communicate (SMB/Samba)"
	read -rp "$(echo -e "${CYAN}Select option [1-2]: ${NC}")" -e -i "1" CLIENT_ISOLATION
	until [[ "$CLIENT_ISOLATION" =~ ^[1-2]$ ]]; do
		echo -e "  ${RED}Invalid option!${NC}"
		read -rp "$(echo -e "${CYAN}Select option [1-2]: ${NC}")" -e -i "1" CLIENT_ISOLATION
	done

	case "$CLIENT_ISOLATION" in
		1)
			ISOLATION_POSTUP="; iptables -I FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_WG_NIC} -j DROP"
			ISOLATION_POSTDOWN="; iptables -D FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_WG_NIC} -j DROP"
			;;
		2)
			ISOLATION_POSTUP=""
			ISOLATION_POSTDOWN=""
			;;
	esac

	echo -e "\n${CYAN}-----------------------------------------------------${NC}"
	echo -e " ${BOLD}${GREEN}✔ Configuration ready to apply!${NC}"
	echo -e "${CYAN}-----------------------------------------------------${NC}\n"
	read -n1 -r -p "Press any key to continue installation..."
}

function installWireGuard() {
	installQuestions

	echo -e "\n${GREEN}[1/5] Updating repositories and installing packages...${NC}"
	apt-get update
	apt-get install -y wireguard-go wireguard-tools iptables iptables-persistent qrencode curl resolvconf

	echo -e "\n${GREEN}[2/5] Creating configuration directory...${NC}"
	mkdir -p /etc/wireguard
	chmod 700 /etc/wireguard

	echo -e "\n${GREEN}[3/5] Generating server private & public keys...${NC}"
	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(wg pubkey <<< "$SERVER_PRIV_KEY")

	if [[ -z "$SERVER_PRIV_KEY" ]] || [[ -z "$SERVER_PUB_KEY" ]]; then
		echo -e "${RED}Error: Failed to generate WireGuard keys.${NC}"
		exit 1
	fi

	echo -e "\n${GREEN}[4/5] Writing configuration to /etc/wireguard/${SERVER_WG_NIC}.conf...${NC}"

	# Write configuration to wg0.conf
	cat <<EOF > /etc/wireguard/${SERVER_WG_NIC}.conf
[Interface]
Address = ${SERVER_WG_IPV4}/24
PrivateKey = ${SERVER_PRIV_KEY}
ListenPort = ${SERVER_PORT}
PostUp = iptables -A INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT; iptables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_NIC} -j MASQUERADE${ISOLATION_POSTUP}
PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT; iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_NIC} -j MASQUERADE${ISOLATION_POSTDOWN}
EOF

	chmod 600 /etc/wireguard/${SERVER_WG_NIC}.conf

	# Safely enable IP Forwarding
	echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
	sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
	sysctl -p /etc/sysctl.d/99-wireguard.conf >/dev/null 2>&1

	if command -v netfilter-persistent &>/dev/null; then
		netfilter-persistent save >/dev/null 2>&1
	fi

	echo -e "\n${GREEN}[5/5] Enabling and starting WireGuard service...${NC}"
	systemctl enable wg-quick@${SERVER_WG_NIC}
	systemctl restart wg-quick@${SERVER_WG_NIC}

	echo -e "\n${GREEN}WireGuard (wireguard-go) installed successfully!${NC}"

	newClient
}

function newClient() {
	echo -e "\n${GREEN}--- Add New WireGuard Client ---${NC}"
    echo ""
	read -rp "Client name (e.g., android-phone): " CLIENT_NAME
	CLIENT_NAME=$(echo "$CLIENT_NAME" | sed 's/[^a-zA-Z0-9_-]//g')

	if [ -z "$CLIENT_NAME" ]; then
		CLIENT_NAME="client1"
	fi

	# FIX 1: Ambil kembali Server Public Key dari file wg0.conf secara otomatis
	if [ -z "$SERVER_PUB_KEY" ]; then
		SERVER_PRIV_KEY=$(grep PrivateKey /etc/wireguard/${SERVER_WG_NIC}.conf | awk '{print $3}')
		SERVER_PUB_KEY=$(wg pubkey <<< "$SERVER_PRIV_KEY")
	fi

	# FIX 2: Ambil parameter server jika dieksekusi dari menu utama
	if [ -z "$SERVER_WG_IPV4" ]; then
		SERVER_WG_IPV4=$(grep Address /etc/wireguard/${SERVER_WG_NIC}.conf | awk '{print $3}' | cut -d'/' -f1)
	fi
	if [ -z "$SERVER_PORT" ]; then
		SERVER_PORT=$(grep ListenPort /etc/wireguard/${SERVER_WG_NIC}.conf | awk '{print $3}')
	fi
	if [ -z "$SERVER_PUB_IP" ]; then
		SERVER_PUB_IP=$(curl -s4 --connect-timeout 5 https://ifconfig.me || curl -s4 --connect-timeout 5 https://api.ipify.org)
	fi
	if [ -z "$CLIENT_DNS" ]; then
		# Ambil settingan DNS yang pernah disimpan di komentar wg0.conf
		CLIENT_DNS=$(grep "# Default DNS Settings for Clients:" /etc/wireguard/${SERVER_WG_NIC}.conf | cut -d':' -f2 | xargs)
		if [ -z "$CLIENT_DNS" ]; then
			CLIENT_DNS="1.1.1.1, 1.0.0.1" # Fallback jika tidak ditemukan
		fi
	fi

	# Generate Client Keys
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(wg pubkey <<< "$CLIENT_PRIV_KEY")
	CLIENT_PRE_KEY=$(wg genpsk)

	if [[ -z "$CLIENT_PRIV_KEY" ]] || [[ -z "$CLIENT_PUB_KEY" ]]; then
		echo -e "${RED}Error: Failed to generate WireGuard keys.${NC}"
		exit 1
	fi

	# Cari IP client berikutnya
	OCTET=2
	while grep -q "10.66.66.${OCTET}" /etc/wireguard/${SERVER_WG_NIC}.conf; do
		((OCTET++))
	done
	CLIENT_WG_IPV4="10.66.66.${OCTET}"

	# Tambahkan Peer ke server config
	cat <<EOF >> /etc/wireguard/${SERVER_WG_NIC}.conf

[Peer]
# Client: ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32
EOF

	# Reload live interface
	wg syncconf ${SERVER_WG_NIC} <(wg-quick strip ${SERVER_WG_NIC})

	# Generate Client Config File (DNS diarahkan langsung ke DNS Provider publik melalui VPN)
	CLIENT_FILE="/root/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
	cat <<EOF > "$CLIENT_FILE"
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_KEY}
Endpoint = ${SERVER_PUB_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

	chmod 600 "$CLIENT_FILE"

	echo -e "\n${GREEN}Client '${CLIENT_NAME}' created successfully!${NC}"
	echo -e "\nProfile file saved to: ${GREEN}${CLIENT_FILE}${NC}\n"
	
	# Render QR Code
	qrencode -t ansiutf8 < "$CLIENT_FILE"
    echo ""
}

function revokeClient() {
	echo -e "\n${GREEN}--- Remove WireGuard Client ---${NC}"
	echo ""

	# Simpan daftar nama klien ke dalam array
	CLIENT_LIST=($(grep '^# Client:' /etc/wireguard/${SERVER_WG_NIC}.conf | awk '{print $3}'))
	NUMBER_OF_CLIENTS=${#CLIENT_LIST[@]}

	if [ "$NUMBER_OF_CLIENTS" -eq 0 ]; then
		echo "No client configurations found."
		exit 0
	fi

	# Tampilkan daftar klien dengan nomor urut 1, 2, 3...
	for ((i=0; i<NUMBER_OF_CLIENTS; i++)); do
		echo "  $((i+1))) ${CLIENT_LIST[$i]}"
	done
	echo ""

	# Input nomor klien
	read -rp "Select client number to revoke [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
	until [[ "$CLIENT_NUMBER" =~ ^[0-9]+$ ]] && [ "$CLIENT_NUMBER" -ge 1 ] && [ "$CLIENT_NUMBER" -le "$NUMBER_OF_CLIENTS" ]; do
		echo "$CLIENT_NUMBER: invalid selection"
		read -rp "Select client number to revoke [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
	done

	# Ambil nama klien berdasarkan indeks array (dikurangi 1)
	REMOVE_CLIENT_NAME="${CLIENT_LIST[$((CLIENT_NUMBER-1))]}"

	# Hapus blok [Peer] dari file wg0.conf
	sed -i "/^\[Peer\]$/{N;/# Client: ${REMOVE_CLIENT_NAME}\$/!b; :a; N; /AllowedIPs/!ba; d}" /etc/wireguard/${SERVER_WG_NIC}.conf

	# Sync konfigurasi live WireGuard
	wg syncconf ${SERVER_WG_NIC} <(wg-quick strip ${SERVER_WG_NIC})

	# Hapus file konfigurasi .conf klien dari /root/ jika ada
	rm -f /root/${SERVER_WG_NIC}-client-${REMOVE_CLIENT_NAME}.conf

	echo -e "\n${GREEN}Client '${REMOVE_CLIENT_NAME}' removed successfully!${NC}"
    echo ""
}

function uninstallWireGuard() {
	echo -e "\n${RED}Uninstalling WireGuard and resetting system settings...${NC}"

	# 1. Pastikan SERVER_WG_NIC terdefinisi
	if [ -z "$SERVER_WG_NIC" ]; then
		SERVER_WG_NIC="wg0"
	fi

	# 2. Ambil Port dan Interface dari file konfigurasi SEBELUM dihapus
	CONF_FILE="/etc/wireguard/${SERVER_WG_NIC}.conf"
	if [ -f "$CONF_FILE" ]; then
		SERVER_PORT=$(grep -i '^ListenPort' "$CONF_FILE" | awk '{print $3}')
	fi

	# Stop service agar PostDown dieksekusi secara native oleh WireGuard
	systemctl stop wg-quick@${SERVER_WG_NIC} 2>/dev/null
	systemctl disable wg-quick@${SERVER_WG_NIC} 2>/dev/null

	echo -e "${GREEN}[1/4] Resetting iptables rules...${NC}"
	
	# Fallback: Jika SERVER_PORT terdeteksi, sapu bersih rule di iptables
	if [ -n "$SERVER_PORT" ]; then
		while iptables -C INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT 2>/dev/null; do
			iptables -D INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT
		done
	fi

	# Sapu bersih rule default WireGuard (51820) jika ada sisa instalasi lama
	while iptables -C INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null; do
		iptables -D INPUT -p udp --dport 51820 -j ACCEPT
	done

	# Bersihkan rule FORWARD dan NAT
	while iptables -C FORWARD -i "${SERVER_WG_NIC}" -j ACCEPT 2>/dev/null; do
		iptables -D FORWARD -i "${SERVER_WG_NIC}" -j ACCEPT
	done
	while iptables -C FORWARD -i "${SERVER_WG_NIC}" -o "${SERVER_WG_NIC}" -j DROP 2>/dev/null; do
		iptables -D FORWARD -i "${SERVER_WG_NIC}" -o "${SERVER_WG_NIC}" -j DROP
	done
	if [ -n "$SERVER_NIC" ]; then
		while iptables -t nat -C POSTROUTING -o "${SERVER_NIC}" -j MASQUERADE 2>/dev/null; do
			iptables -t nat -D POSTROUTING -o "${SERVER_NIC}" -j MASQUERADE
		done
	fi

	# Simpan perubahan iptables
	if command -v netfilter-persistent &>/dev/null; then
		netfilter-persistent save >/dev/null 2>&1
	fi

	echo -e "${GREEN}[2/4] Resetting sysctl configuration...${NC}"
	if [ -f /etc/sysctl.d/99-wireguard.conf ]; then
		rm -f /etc/sysctl.d/99-wireguard.conf
	fi

	sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
	sysctl --system >/dev/null 2>&1

	echo -e "${GREEN}[3/4] Removing WireGuard packages...${NC}"
	apt-get remove --purge -y wireguard-go wireguard-tools

	echo -e "${GREEN}[4/4] Cleaning configuration files...${NC}"
	rm -rf /etc/wireguard
	rm -f /root/${SERVER_WG_NIC}-client-*.conf

	echo -e "\n${GREEN}WireGuard has been uninstalled!${NC}"
    echo ""
}

# Main Execution Flow
initialCheck

if [ -f "/etc/wireguard/wg0.conf" ]; then
	SERVER_WG_NIC="wg0"
	echo -e "\n${GREEN}WireGuard is already installed on this system.${NC}"
    echo ""
	echo "1) Add New Client"
	echo "2) Revoke Existing Client"
	echo "3) Uninstall WireGuard"
	echo "4) Exit"
    echo ""
	read -rp "Select option [1-4]: " MENU_OPTION
	case "$MENU_OPTION" in
		1) newClient ;;
		2) revokeClient ;;
		3) uninstallWireGuard ;;
		*) exit 0 ;;
	esac
else
	installWireGuard
fi
