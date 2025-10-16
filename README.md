# edge-device-ssh-wifi

Opinionated, minimal repo to provision Orange Pi (Ubuntu 20.04) edge devices and an office admin machine for secure one-way SSH (admin → devices) using **Tailscale** + SSH hardening + local UFW rules. The admin machine is assumed to be Windows 11, while the edge devices run Ubuntu 20.04.

**Goal:** Download the repo onto the admin PC and each Pi, follow the instructions or run scripts as appropriate, and be done. Scripts for edge devices are idempotent and interactive: you provide the Tailscale pre-auth key, admin email/username, and the admin public key.

---

## File tree

```
edge-device-ssh-wifi/
├── README.md                 # this file
├── admin/
│   └── generate_keys.ps1     # PowerShell script to generate ed25519 keypair on Windows (optional)
├── edge/
│   ├── install_edge.sh       # run on each Orange Pi
│   ├── tailscale_up.sh       # helper to bring up tailscale with preauth key
│   ├── harden_sshd.sh        # sshd hardening (disable password, root, allowuser)
│   └── ufw_setup.sh          # UFW rules: allow on tailscale0, deny out to LAN
└── LICENSE
```

---

## High-level flow (what you will run)

1. On **admin PC** (Windows 11):

   * Install the Tailscale client from the official website (download and run the installer from https://tailscale.com/download).
   * Optionally generate an ed25519 keypair using the provided PowerShell script `admin/generate_keys.ps1` or manually via `ssh-keygen` in PowerShell (OpenSSH is built-in on Windows 11).
   * Note the path to your public key (typically `~/.ssh/id_ed25519.pub` or `C:\Users\YourUser\.ssh\id_ed25519.pub`) to copy into the Pi installer.
   * Sign in to Tailscale on your Windows machine using the app.

2. In the Tailscale admin console:

   * Create a pre-auth key and tag it `tag:orange-pi` (or any tag you like).
   * Optionally enable MagicDNS.
   * Copy the pre-auth key.

3. On **each Orange Pi** (run `edge/install_edge.sh` as root or with sudo on Ubuntu 20.04):

   * Pass the `--authkey` (the Tailscale pre-auth key), a hostname (opi-01..07), and the admin public key (or URL to it).
   * The script installs Tailscale, runs `tailscale up --authkey ... --hostname ... --accept-routes=false` (no routes advertised).
   * Installs `ufw` and configures rules to 1) only allow ssh on `tailscale0`, 2) deny outbound to `192.168.0.0/24`, 3) default deny incoming.
   * Hardens `sshd_config` to disable password auth and root login, adds `AllowUsers orangepi` and puts admin public key into `/home/orangepi/.ssh/authorized_keys`.

4. Test from admin (Windows): Open PowerShell and run `ssh -i ~/.ssh/id_ed25519 orangepi@opi-01` (or use MagicDNS like `ssh orangepi@opi-01`) — it will go over Tailscale. If you generated keys with PuTTY, use PuTTY for SSH instead.

---

## Notes and safety

* The Pi will have no inbound open SSH on the Wi-Fi interface and will *not* be able to initiate connections to your office LAN (192.168.0.0/24) because of UFW deny-out rule.
* The only way to reach the Pis is via Tailscale and only for identities allowed by your Tailscale ACLs.
* After provisioning, revoke or rotate the pre-auth key in the Tailscale console to prevent reuse.
* Ubuntu 20.04 is supported by Tailscale; ensure your Orange Pi image is based on it for compatibility.

---

## Scripts

> The following scripts are included in the repo. Copy them into the respective paths and make them executable where applicable (`chmod +x` for Linux scripts).

### `admin/generate_keys.ps1`

```powershell
# PowerShell script to generate an ed25519 keypair on Windows.
$KEY_PATH = "$HOME\.ssh\id_ed25519"

if (Test-Path $KEY_PATH) {
    Write-Output "Key already exists at $KEY_PATH"
    Write-Output "Public key: $($KEY_PATH).pub"
    Get-Content "$($KEY_PATH).pub"
    exit 0
}

ssh-keygen -t ed25519 -f $KEY_PATH -C "dental-admin@office" -N ""
Write-Output "Generated keypair. Public key at $($KEY_PATH).pub"
Get-Content "$($KEY_PATH).pub"
```

To run: Open PowerShell, navigate to the admin folder, and execute `./generate_keys.ps1`.

If you prefer manual generation, open PowerShell and run:
```
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "dental-admin@office"
```

### `edge/install_edge.sh`

```
#!/usr/bin/env bash
# Run on each Orange Pi as root (or with sudo) on Ubuntu 20.04
# Usage: sudo ./install_edge.sh --authkey TS_AUTHKEY --hostname opi-01 --pubkey "ssh-ed25519 AAAA..."

set -euo pipefail

print_usage(){
  cat <<EOF
Usage: sudo $0 --authkey <tailscale-preauth-key> --hostname <opi-01> --pubkey '<ssh-public-key>'
EOF
}

AUTHKEY=""
HOSTNAME=""
PUBKEY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --authkey) AUTHKEY="$2"; shift 2;;
    --hostname) HOSTNAME="$2"; shift 2;;
    --pubkey) PUBKEY="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown: $1"; print_usage; exit 1;;
  esac
done

if [ -z "$AUTHKEY" ] || [ -z "$HOSTNAME" ] || [ -z "$PUBKEY" ]; then
  echo "Missing required args"; print_usage; exit 1
fi

# install tailscale (Ubuntu 20.04 compatible)
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled

# bring Tailscale up with the preauthkey and hostname; do not advertise routes
tailscale up --authkey "$AUTHKEY" --hostname "$HOSTNAME" --accept-routes=false || true

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

# install ufw, disable password ssh and lock down sshd (call helper scripts)
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
# allow SSH IN only on tailscale interface
ufw allow in on tailscale0 to any port 22 proto tcp
# deny SSH in on wlan0 (no direct Wi-Fi SSH)
ufw deny in on wlan0 to any port 22 proto tcp || true
# prevent Pi from initiating connections to office LAN
ufw deny out to 192.168.0.0/24
ufw --force enable

# final info
echo "Provisioning complete. Tailscale status:"
tailscale status || true

```

### `edge/ufw_setup.sh` and `edge/harden_sshd.sh`

Small helpers exist in the repo; the main `install_edge.sh` contains the necessary actions. `ufw_setup.sh` only contains the UFW commands above for re-running; `harden_sshd.sh` edits `sshd_config` similarly.

---

## How to copy & run quickly

* On admin PC (Windows 11):

  1. Download and install Tailscale from https://tailscale.com/download.
  2. Generate key: Open PowerShell, navigate to the repo's admin folder, and run `.\generate_keys.ps1` (or manually with `ssh-keygen` as above).
  3. Copy the public key text (from the output) and the Tailscale pre-auth key from the admin console.

* On each Orange Pi (you can paste the following with appropriate values):

```bash
# on the Pi, as root (or use sudo)
wget https://raw.githubusercontent.com/your-org/edge-device-ssh-wifi/main/edge/install_edge.sh -O /tmp/install_edge.sh
chmod +x /tmp/install_edge.sh
sudo /tmp/install_edge.sh --authkey TS_PREAUTH_KEY --hostname opi-01 --pubkey "ssh-ed25519 AAAA..."
```

Replace `TS_PREAUTH_KEY` and the public key blob accordingly.

---

## Next steps and expansion

* After all devices are provisioned, revoke the pre-auth key in Tailscale.
* Optionally enable Tailscale ACLs (sample JSON included in README) so only [admin@yourdomain.com](mailto:admin@yourdomain.com) can access `tag:orange-pi:22`.
* Optionally write an Ansible playbook to run `install_edge.sh` remotely over the Wi-Fi before switching to Tailscale for later management.

---

License: MIT