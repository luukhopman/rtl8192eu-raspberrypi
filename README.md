# RTL8192EU on Raspberry Pi, with a safe fallback

One command to switch an RTL8192EU USB Wi-Fi stick from the in-kernel
`rtl8xxxu` driver to Realtek's driver, without the risk of cutting off a
headless Pi.

The in-kernel `rtl8xxxu` driver drops these sticks off the network in bursts
(hundreds of `CTRL-EVENT-BEACON-LOSS` events an hour, even at full signal).
Realtek's driver, as maintained in
[Mange/rtl8192eu-linux-driver](https://github.com/Mange/rtl8192eu-linux-driver),
held a steady link where `rtl8xxxu` did not.

## What the installer does

1. Checks for a supported stick and picks the build for your CPU (32-bit
   Raspberry Pi OS, 64-bit Raspberry Pi OS, or x86).
2. Installs the build tools and kernel headers, and builds the driver with
   **DKMS**, so kernel updates rebuild it automatically.
3. **Trials** the driver: it switches the stick over and waits up to 2 minutes
   for the stick's own interface to reach its gateway. If it does not, it goes
   back to `rtl8xxxu` and removes everything it built.
4. Only after a successful trial, blacklists `rtl8xxxu` and installs a **boot
   safety net**: if the stick has no network 3 minutes after boot, the Pi
   switches back to `rtl8xxxu` by itself.

It runs as a background service, so the SSH session dropping while the Wi-Fi
switches over does not interrupt it.

## Usage

```bash
git clone https://github.com/luukhopman/rtl8192eu-raspberrypi.git
cd rtl8192eu-raspberrypi
./install.sh
journalctl -fu rtl8192eu-install     # follow progress; ends with "Success" or a rollback
```

The build takes 20–40 minutes on a Pi 2 and a few minutes on a Pi 4.

```bash
./install.sh --status      # which driver each interface uses, DKMS and fallback state
./install.sh --uninstall   # remove everything and return to rtl8xxxu
./install.sh --foreground  # install in the current terminal instead
```

The driver loads with `rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0` to keep
the stick out of power saving (`/etc/modprobe.d/8192eu.conf`).

## Supported sticks

USB IDs claimed by the driver build:

| Vendor | IDs |
| --- | --- |
| TP-Link | `2357:0107`, `2357:0108`, `2357:0109`, `2357:0126` |
| D-Link | `2001:3312`, `2001:3319` |
| Mercusys | `2c4e:0100`, `2c4e:0104` |
| Planex | `2019:ab33` |
| Realtek reference | `0bda:818b`, `0bda:818c` |

Find yours with `lsusb`. Tested on a TP-Link TL-WN823N v2/v3 (`2357:0109`) with
a Raspberry Pi 2 Model B on Raspberry Pi OS 12 (bookworm, 32-bit). The 64-bit
and x86 paths use the upstream build flags but are untested; reports welcome.

## Notes

- Every Raspberry Pi from the Pi 3 on has built-in Wi-Fi, so this is mostly
  useful for a Pi 1 or 2, or for a second Wi-Fi interface.
- On a Pi 2, a webcam or other power-hungry USB device can reset the whole USB
  bus when it starts (`usb usb1-port1: disabled by hub (EMI?)`), taking the
  stick down for a few seconds. Use a solid 2.5 A supply or a powered USB hub.

## Licence

The installer is MIT licensed (see `LICENSE`). It downloads and builds
GPL-licensed Realtek code from Mange/rtl8192eu-linux-driver at commit
`c629cc972a0d878c930d19c4a9309c27c1e61f92`.
