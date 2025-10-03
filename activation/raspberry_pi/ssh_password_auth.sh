#!/usr/bin/env bash
# Toggle SSH PasswordAuthentication on/off, with backup + validation.
# Usage: sudo ./ssh-password-auth.sh enable|disable

set -euo pipefail

ACTION="${1:-}"
if [[ "$ACTION" != "enable" && "$ACTION" != "disable" ]]; then
  echo "Usage: sudo $0 enable|disable"
  echo "  enable  = allow username+password logins"
  echo "  disable = key-only (PasswordAuthentication no)"
  exit 2
fi

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0 $ACTION"
  exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${SSHD_CONFIG}.bak-${STAMP}"

# Pick the right systemd service name (Ubuntu: ssh; some distros: sshd)
SERVICE="ssh"
if systemctl list-unit-files | grep -q '^sshd\.service'; then
  SERVICE="sshd"
fi

echo "Creating backup: $BACKUP"
cp -a "$SSHD_CONFIG" "$BACKUP"

# Normalize any existing directive (commented or not), then set desired state
if [[ "$ACTION" == "enable" ]]; then
  DESIRED="yes"
  MSG="Enabling password authentication (PasswordAuthentication yes)"
else
  DESIRED="no"
  MSG="Disabling password authentication (PasswordAuthentication no)"
fi
echo "$MSG"

# If directive exists (commented or not), replace it; otherwise append at end
if grep -Eq '^[#[:space:]]*PasswordAuthentication[[:space:]]+' "$SSHD_CONFIG"; then
  sed -i 's/^[#[:space:]]*PasswordAuthentication[[:space:]]\+.*/PasswordAuthentication '"$DESIRED"'/g' "$SSHD_CONFIG"
else
  printf "\nPasswordAuthentication %s\n" "$DESIRED" >> "$SSHD_CONFIG"
fi

# Optional: make sure PubkeyAuthentication remains on (good default)
if ! grep -Eq '^[#[:space:]]*PubkeyAuthentication[[:space:]]+' "$SSHD_CONFIG"; then
  echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
else
  sed -i 's/^[#[:space:]]*PubkeyAuthentication[[:space:]]\+.*/PubkeyAuthentication yes/g' "$SSHD_CONFIG"
fi

# Validate config before restarting
if command -v sshd >/dev/null 2>&1; then
  sshd -t
elif command -v /usr/sbin/sshd >/dev/null 2>&1; then
  /usr/sbin/sshd -t
else
  echo "Warning: could not find sshd binary to validate config; proceeding to restart."
fi

echo "Restarting $SERVICE…"
systemctl restart "$SERVICE"

# Show the effective setting
EFF=$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}' || true)
echo "Done. Effective PasswordAuthentication: ${EFF:-unknown}"
echo "Backup saved at: $BACKUP"
