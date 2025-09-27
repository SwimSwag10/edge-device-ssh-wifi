#!/bin/bash

# Plug-and-play activation script for Orange Pi edge device
# Run as sudo: sudo ./activation.sh
# Assumes: Ethernet connected for initial internet, WiFi adapter plugged in.

set -e  # Exit on error

# Function to check and install WiFi driver
check_install_driver() {
  if lsmod | grep -q 8821au; then
    echo "WiFi driver (8821au) already installed."
  else
    echo "Installing WiFi driver for TP-Link Archer T2U Nano..."
    apt install -y build-essential dkms git linux-headers-$(uname -r) bc iw
    git clone https://github.com/morrownr/8821au-20210708.git || true
    cd 8821au-20210708
    ./install-driver.sh
    cd ..
    echo "Driver installed. Rebooting in 5 seconds to load module..."
    sleep 5
    reboot
  fi
}

# Function to detect WiFi interface
detect_wifi_interface() {
  sleep 2  # Give time for adapter detection
  INTERFACE=$(ip link | grep -o 'wlx[0-9a-f]*' | head -n1)
  if [ -z "$INTERFACE" ]; then
    echo "Error: No WiFi interface detected. Ensure TP-Link adapter is plugged in and driver loaded."
    exit 1
  fi
  echo "Detected WiFi interface: $INTERFACE"
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
  apt install -y avahi-daemon
  systemctl enable avahi-daemon
  systemctl start avahi-daemon
  echo "Hostname set to $HOSTNAME. Discoverable via mDNS as $HOSTNAME.local"
}

# Function to configure WiFi via Netplan
setup_netplan() {
  NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
  cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  wifis:
    $INTERFACE:
      dhcp4: ${USE_STATIC,, = "y" ? false : true}
EOF
  if [ "${USE_STATIC,,}" = "y" ]; then
    echo "      addresses: [$STATIC_IP$SUBNET]" >> $NETPLAN_FILE
    echo "      gateway4: $GATEWAY" >> $NETPLAN_FILE
  fi
  cat <<EOF >> $NETPLAN_FILE
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      access-points:
        "$SSID":
          password: "$PASSWORD"
  ethernets:
    all-eth:
      match:
        name: "e*"
      dhcp4: false
      optional: true
EOF
  netplan apply
  echo "Netplan configured for WiFi. Ethernet disabled."
}

# Function to setup SSH (integrated from setup_ssh.sh)
setup_ssh() {
  apt install -y openssh-server
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

apt update
apt install -y netplan.io

check_install_driver
detect_wifi_interface
prompt_user
setup_hostname_mdns
setup_netplan
setup_ssh
generate_config
test_wifi  # Verify before reboot

echo "Setup complete! Disconnect Ethernet, reboot, and from any desktop terminal on the network:"
echo "  ssh ubuntu@$HOSTNAME.local"
echo "  (On Windows, use PuTTY or enable OpenSSH: ssh ubuntu@$HOSTNAME.local)"
echo "For multiple devices, repeat on each with unique operatoryID."
echo "Rebooting in 10 seconds..."
sleep 10
reboot