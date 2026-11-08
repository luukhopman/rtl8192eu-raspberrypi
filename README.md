# RTL8192EU on Raspberry Pi, with a safe fallback

Build, trial and install the Realtek RTL8192EU driver for USB Wi-Fi sticks such
as the TP-Link TL-WN823N v2/v3 (`2357:0109`) on Raspberry Pi OS, without the
risk of losing a headless Pi.

The in-kernel `rtl8xxxu` driver drops this stick off the network in bursts
(hundreds of `CTRL-EVENT-BEACON-LOSS` events an hour, even at full signal).
Realtek's driver, as maintained in
[Mange/rtl8192eu-linux-driver](https://github.com/Mange/rtl8192eu-linux-driver),
held a steady link in testing on a Raspberry Pi 2 Model B.

Tested on Raspberry Pi OS 12 (bookworm, 32-bit), kernel `6.12.115+rpt-rpi-v7`.

## Safety net

Changing the Wi-Fi driver on a headless Pi can cut you off, so both steps fall
back on their own:

- `test-driver.sh` loads the driver for this session only. If there is no
  network within 2 minutes, it unloads it and loads `rtl8xxxu` again. A reboot
  always returns to `rtl8xxxu`.
- `install-driver.sh` makes the driver permanent and installs
  `wifi-driver-fallback.service`. If there is no network 3 minutes after boot,
  it removes the `rtl8xxxu` blacklist and loads `rtl8xxxu`. This also covers a
  kernel update that leaves the module behind.

## Usage

The scripts expect everything in `/home/pi/wifi-driver`.

```bash
sudo apt-get install -y git build-essential linux-headers-rpi-v7
git clone https://github.com/luukhopman/rtl8192eu-raspberrypi.git ~/rtl8192eu-raspberrypi
mkdir -p ~/wifi-driver && cp ~/rtl8192eu-raspberrypi/*.sh ~/wifi-driver/
git clone https://github.com/Mange/rtl8192eu-linux-driver.git ~/wifi-driver/rtl8192eu-linux-driver
git -C ~/wifi-driver/rtl8192eu-linux-driver checkout c629cc972a0d878c930d19c4a9309c27c1e61f92

~/wifi-driver/build.sh            # builds in the background (20–40 min on a Pi 2)
tail ~/wifi-driver/build.log      # wait for EXIT=0
~/wifi-driver/test-driver.sh      # trial; check /var/log/pi-health.log
~/wifi-driver/install-driver.sh   # make it permanent
```

The driver loads with `rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0` to keep
the stick out of power saving.

### Prebuilt module

`8192eu-6.12.115+rpt-rpi-v7.ko` is built for kernel `6.12.115+rpt-rpi-v7` only.
On that kernel you can skip the build:

```bash
sha256sum -c SHA256SUMS
cp 8192eu-6.12.115+rpt-rpi-v7.ko ~/wifi-driver/rtl8192eu-linux-driver/8192eu.ko
```

### After a kernel update

The installed module no longer matches the new kernel, so the boot fallback
switches to `rtl8xxxu`. Install the matching headers, run `build.sh` again, then
`install-driver.sh`.

## Notes for a Pi 2 with more USB devices

The Pi 2 limits current on its USB ports. With a webcam or other power-hungry
device next to the stick, add `max_usb_current=1` to
`/boot/firmware/config.txt` and use a 2.5 A supply; otherwise a device starting
up can reset the whole USB bus, Wi-Fi stick included.

## Licence

The scripts are MIT licensed (see `LICENSE`). The module is built from
GPL-licensed Realtek code; its corresponding source is upstream commit
`c629cc972a0d878c930d19c4a9309c27c1e61f92` of Mange/rtl8192eu-linux-driver with
`rpi-makefile.patch` applied (`build.sh` makes the same change).
