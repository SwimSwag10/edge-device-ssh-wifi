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

## Setup | Plug-and-Play for Edge Devices:
1. Flash Ubuntu 24.04 Server ARM64 to SSD/microSD as per docs/setup_guide.md.
2. Boot Orange Pi with Ethernet connected (for internet), HDMI/keyboard for login.
3. Login (ubuntu/ubuntu, change password).
4. Install git: sudo apt install git.
5. Clone repo: git clone <repo-url> ssh-over-wifi-test && cd ssh-over-wifi-test/edge-device-setup.
6. Plug in TP-Link WiFi adapter.
7. Run activation: sudo ./activation.sh.
8. Follow prompts (SSID, password, operatoryID, etc.).
  - The password should follow this standard: `{OPERATORY_CITY}-{PRACTICE_ID}-{OPERATORY_ID}` where the each of these values are the NexHealth practice values.
9. Script auto-sets up everything; device reboots.
10. Disconnect Ethernet. From desktop, SSH to edge-op<ID>.local (e.g., ssh ubuntu@edge-op1.local).
11. For desktop app: Run node dist/index.js connect --device edge-op1 (discovers via mDNS if needed).