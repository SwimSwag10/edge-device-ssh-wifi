#!/bin/bash

# Plug-and-play activation script for Raspberry Pi 5 edge device on Ubuntu
# Run as sudo: sudo ./activation.sh
# Assumes: Ethernet connected for initial internet (shared from laptop), onboard WiFi available.

# Naming convention: "op4-ubuntu-pi"
# Hostname: "op4-ubuntu-pi"
# username & password (for both): "op4-ubuntu-pi"

set -e  # Exit on error

# Function to detect WiFi interface (hardcoded for RPi)
detect_wifi_interface() {
  INTERFACE="wlan0"
  if [ -z "$(ip link show $INTERFACE 2>/dev/null)" ]; then
    echo "Error: WiFi interface $INTERFACE not detected. Ensure onboard WiFi is enabled."
    exit 1
  fi
  echo "Using WiFi interface: $INTERFACE"
}

# Function to prompt for info
prompt_user() {
  read -p "Enter WiFi SSID: " SSID
  read -s -p "Enter WiFi Password: " PASSWORD
  echo
  read -p "Enter Operatory ID (e.g., 1 for room 1; must be unique per device): " OPERATORY_ID
  read -p "Use static IP? (y/n, default n for DHCP): " USE_STATIC
  if [ "${USE_STATIC,,}" = "y" ]; then
    read -p "Enter static IP for this device (e.g., 192.168.1.100): " STATIC_IP
    read -p "Enter subnet mask (e.g., /24): " SUBNET
    read -p "Enter network gateway (e.g., 192.168.1.1): " GATEWAY
  else
    STATIC_IP=""
    SUBNET=""
    GATEWAY=${GATEWAY:-192.168.1.1}
  fi
  read -p "Paste your desktop's SSH public key (for key-based auth): " PUB_KEY
}

# Function to set hostname and mDNS
setup_hostname_mdns() {
  HOSTNAME="edge-op${OPERATORY_ID}"
  hostnamectl set-hostname "$HOSTNAME"
  sudo apt install -y avahi-daemon
  systemctl enable avahi-daemon
  systemctl start avahi-daemon
  echo "Hostname set to $HOSTNAME. Discoverable via mDNS as $HOSTNAME.local"
}

# Function to configure WiFi via Netplan
setup_netplan() {
  NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"  # Ubuntu default on Pi
  if [ "${USE_STATIC,,}" = "y" ]; then
    DHCP4="false"
  else
    DHCP4="true"
  fi
  cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  wifis:
    $INTERFACE:
      dhcp4: $DHCP4
EOF
  if [ "${USE_STATIC,,}" = "y" ]; then
    echo "      addresses: [$STATIC_IP$SUBNET]" >> $NETPLAN_FILE
    echo "      routes:" >> $NETPLAN_FILE
    echo "        - to: default" >> $NETPLAN_FILE
    echo "          via: $GATEWAY" >> $NETPLAN_FILE
  fi
  cat <<EOF >> $NETPLAN_FILE
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      access-points:
        "$SSID":
          password: "$PASSWORD"
  ethernets:
    eth0:
      dhcp4: false
      optional: true
EOF
  chmod 600 $NETPLAN_FILE  # Set secure permissions
  netplan generate
  netplan apply
  echo "Netplan configured for WiFi. Ethernet disabled."
}

# Function to setup SSH
setup_ssh() {
  sudo apt install -y openssh-server  # Already installed by default, but ensure
  systemctl start ssh
  systemctl enable ssh
  mkdir -p /home/ubuntu/.ssh
  echo "$PUB_KEY" >> /home/ubuntu/.ssh/authorized_keys
  chmod 600 /home/ubuntu/.ssh/authorized_keys
  chown ubuntu:ubuntu /home/ubuntu/.ssh -R
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  systemctl restart ssh
  echo "SSH setup complete. Password auth disabled; use keys only."
}

# Function to generate config
generate_config() {
  cat <<EOF > config.json
{
  "operatoryID": "$OPERATORY_ID",
  "hostname": "$HOSTNAME",
  "wifiInterface": "$INTERFACE",
  "staticIP": "${STATIC_IP:-DHCP}"
}
EOF
  echo "Config file generated: config.json"
}

# Function to test WiFi
test_wifi() {
  echo "Testing WiFi connection (may take a moment)..."
  ip link set $INTERFACE up
  sleep 10
  if ping -c 3 8.8.8.8 &> /dev/null; then
    echo "WiFi test successful!"
  else
    echo "Warning: WiFi test failed. Check SSID/password and try again."
    exit 1
  fi
}

# Main execution
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

sudo apt update
# sudo apt install -y netplan.io  # Already installed on Ubuntu

detect_wifi_interface
prompt_user
setup_hostname_mdns
setup_netplan
setup_ssh
generate_config
test_wifi  # Verify before reboot

echo "Setup complete! Disconnect Ethernet, reboot, and from any desktop terminal on the network:"
echo "  ssh ubuntu@$HOSTNAME.local"
echo "  (On Windows, use ssh ubuntu@$HOSTNAME.local)"
echo "For multiple devices, repeat on each with unique operatoryID."
echo "Rebooting in 10 seconds..."
sleep 10
reboot