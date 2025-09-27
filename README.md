## Overview
This project is so that we can have an edge device(s) in dental practices. There will be one singular device inside of the office that we can access all of the edge devices from. This device can be specified at the time appointed.

Remember:
1. We will have a desktop that needs to access one or multiple edge devices inside of the dental practice.
2. The edge device(s) is a Orange Pi (ARM64 Ubuntu architecture).
3. There is a LAN inside of the offices that all of the desktops in the office are connected to (over Cat6), but I do not want to rely on this. We should be able to do this over wifi I think.
4. The edge device(s) has a `TP-Link Nano AC600 USB WiFi Adapter(Archer T2U Nano)- 2.4G/5G Dual Band Wireless Network Transceiver for PC Desktop, Travel Size, Supports Windows (11,10, 8.1, 8, 7, XP/Mac OS X 10.9-10.14)` in one of the device's ports.

## Project Directory structure
This is where we will house the directory structure of this test application.
```
ssh-over-wifi-test/
├── activation.sh   # Automated activation
└── README.md       # Update with plug-and-play flow
```

## Setup
This repo is cloned and run only on the Orange Pi edge devices to configure WiFi and SSH. No code needed on the desktop. Just use your terminal to SSH after the edge device is setup.

1. Flash Ubuntu 24.04 Server ARM64 to SSD/microSD (see docs/setup_guide.md).
2. Boot with Ethernet connected, login (ubuntu/ubuntu, change password).
3. Run this:
```shell
sudo apt install git
```
4. Run this:
```shell
git clone <repo-url> ssh-over-wifi-test
```
5. Plug in TP-Link WiFi adapter.
6. Activate the shell automation. The password should follow this standard: `{OPERATORY_CITY}-{PRACTICE_ID}-{OPERATORY_ID}` where each of these values are the NexHealth practice values. Run this (follow prompts for SSID, password, operatoryID, etc.):
```shell
sudo ./activation.sh
```
7. Device reboots automatically.
8. Disconnect Ethernet. From desktop terminal: ssh ubuntu@edge-op<ID>.local (e.g., edge-op1.local).
9. For Windows: Install PuTTY or enable OpenSSH in Settings > Apps > Optional Features.

If mDNS (.local) doesn't resolve (rare on some networks), use ip a on the edge device to get its IP and SSH to that instead.