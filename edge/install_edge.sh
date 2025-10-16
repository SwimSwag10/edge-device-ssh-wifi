#!/usr/bin/env bash
# Run on each Orange Pi as root (or with sudo) on Ubuntu 20.04
# Usage: sudo ./install_edge.sh --hostname opi-01 --pubkey "ssh-ed25519 AAAA..." --admin_ip 192.168.0.100

set -euo pipefail

print_usage(){
  cat <<EOF
Usage: sudo $0 --hostname <opi-01> --pubkey '<ssh-public-key>' --admin_ip <admin-lan-ip>
EOF
}

HOSTNAME=""
PUBKEY=""
ADMIN_IP=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --hostname) HOSTNAME="$2"; shift 2;;
    --pubkey) PUBKEY="$2"; shift 2;;
    --admin_ip) ADMIN_IP="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown: $1"; print_usage; exit 1;;
  esac
done

if [ -z "$HOSTNAME" ] || [ -z "$PUBKEY" ] || [ -z "$ADMIN_IP" ]; then
  echo "Missing required args"; print_usage; exit 1
fi

# Set hostname
hostnamectl set-hostname "$HOSTNAME"

# create user 'orangepi' if missing (some images already have it)
if ! id -u orangepi >/dev/null 2>&1; then
  useradd -m -s /bin/bash orangepi
fi

# setup ssh directory and authorized_keys
mkdir -p /home/orangepi/.ssh
chmod 700 /home/orangepi/.ssh
echo "$PUBKEY" > /home/orangepi/.ssh/authorized_keys
chmod 600 /home/orangepi/.ssh/authorized_keys
chown -R orangepi:orangepi /home/orangepi/.ssh

# install ufw and openssh-server
apt-get update && apt-get install -y ufw openssh-server

# Harden sshd_config: disable PasswordAuthentication, PermitRootLogin no, AllowUsers orangepi
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -ri 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
# ensure AllowUsers line exists (idempotent)
if ! grep -q "^AllowUsers" /etc/ssh/sshd_config; then
  echo "AllowUsers orangepi" >> /etc/ssh/sshd_config
else
  sed -ri 's/^AllowUsers.*/AllowUsers orangepi/' /etc/ssh/sshd_config
fi
systemctl restart ssh

# UFW config
ufw --force reset
ufw default allow outgoing
ufw default deny incoming
# allow SSH IN only from admin IP on wlan0
ufw allow in on wlan0 from "$ADMIN_IP" to any port 22 proto tcp
# prevent Pi from initiating connections to office LAN
ufw deny out to 192.168.0.0/24
ufw --force enable

# final info
echo "Provisioning complete. Pi hostname: $HOSTNAME"
echo "SSH from admin: ssh -i ~/.ssh/id_ed25519 orangepi@$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
