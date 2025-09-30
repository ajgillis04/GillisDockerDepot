#!/bin/bash
#
# Script Name: genwireguardpeers.sh
# Author: Andy Gillis
# Date: 2025-09-23
#
# Description:
#   Generates WireGuard client keypairs and configuration files for a predefined list of peers.
#   Prompts before overwriting existing keys or configs.
#   Uses a shared server public key and endpoint to build ready-to-import .conf files.
#
# Usage:
#   chmod +x genwireguardpeers.sh
#   dos2unix genwireguardpeers.sh   # if saved in Windows
#   ./genwireguardpeers.sh
#
# Prerequisites:
#   - Bash shell (Linux, WSL, or Git Bash)
#   - WireGuard tools installed (`wg` command available)
#   - Script run from a directory where `server/` and `clients/` folders can be created
#   - VPN endpoint and DNS values set in the config block
#
# Output:
#   - server/server_privatekey and server_publickey
#   - clients/<peer>/<peer>.conf, privatekey, and publickey
#
# Note: This script currently generates IPv4-only configs.
# If you want to add IPv6 support:
#   1. Define an IPv6 base subnet, e.g., ipv6_base="fd00:9::"
#   2. Assign each peer an IPv6 address like "$ipv6_base$ip_suffix/128"
#   3. Update the [Interface] block:
#        Address = $ip/32, $ipv6/128
#   4. Ensure your server has an IPv6 address and firewall rules for UDP/51820
#   5. Add "::/0" to AllowedIPs for full IPv6 tunnel

### === CONFIGURATION === ###
# List of peer names
peers=(
  client1 client2 client3 client4 client5
)

# VPN endpoint and DNS (replace with your actual values)
endpoint="vpn.example.com:51820"
dns="192.168.1.1"
base_ip="10.9.0."
starting_ip_suffix=2
lan_subnet="192.168.1.0/24"
mtu="1280"

# Directory layout
server_dir="server"
clients_dir="clients"

### === SETUP === ###
mkdir -p "$server_dir" "$clients_dir"

# Generate server keys with overwrite prompt
if [ -f "$server_dir/server_privatekey" ]; then
  read -p "Found existing server keys/config. Overwrite? [y/N] " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    wg genkey | tee "$server_dir/server_privatekey" | wg pubkey > "$server_dir/server_publickey"
    echo "Server keys regenerated."
  else
    echo "Keeping existing server keys."
  fi
else
  wg genkey | tee "$server_dir/server_privatekey" | wg pubkey > "$server_dir/server_publickey"
  echo "Server keys generated."
fi

server_pubkey=$(<"$server_dir/server_publickey")
ip_suffix=$starting_ip_suffix

### === CLIENT LOOP === ###
for name in "${peers[@]}"; do
  peer_dir="$clients_dir/$name"
  mkdir -p "$peer_dir"

  if [ -f "$peer_dir/privatekey" ]; then
    read -p "Found existing keys/config for $name. Overwrite? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Skipping $name"
      ((ip_suffix++))
      continue
    fi
  fi

  # Generate client keys
  wg genkey | tee "$peer_dir/privatekey" | wg pubkey > "$peer_dir/publickey"
  priv=$(<"$peer_dir/privatekey")
  ip="${base_ip}${ip_suffix}"

  # Write client config
  cat > "$peer_dir/$name.conf" <<EOF
[Interface]
PrivateKey = $priv
Address = $ip/32
DNS = $dns
MTU = $mtu

[Peer]
PublicKey = $server_pubkey
Endpoint = $endpoint
AllowedIPs = 0.0.0.0/0, ::/0, $lan_subnet
PersistentKeepalive = 25
EOF

  echo "Generated $name.conf → $ip"
  ((ip_suffix++))
done