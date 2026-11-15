#!/bin/bash
# Install Realtek's RTL8192EU driver on Raspberry Pi OS (or Debian) through DKMS,
# trial it, and keep it only if the Wi-Fi stick actually reaches the network.
#
#   ./install.sh               install in the background; follow with journalctl
#   ./install.sh --foreground  install in this terminal (not recommended over SSH)
#   ./install.sh --status      show which driver is in use
#   ./install.sh --uninstall   remove the driver and go back to rtl8xxxu
set -euo pipefail

UPSTREAM="https://github.com/Mange/rtl8192eu-linux-driver.git"
COMMIT="c629cc972a0d878c930d19c4a9309c27c1e61f92"
NAME="rtl8192eu"
VERSION="1.0"
SRC="/usr/src/${NAME}-${VERSION}"
UNIT="rtl8192eu-install"
FALLBACK_BIN="/usr/local/sbin/rtl8192eu-fallback"
FALLBACK_UNIT="/etc/systemd/system/rtl8192eu-fallback.service"
OPTIONS_CONF="/etc/modprobe.d/8192eu.conf"
BLACKLIST_CONF="/etc/modprobe.d/blacklist-rtl8xxxu.conf"
TRIAL_SECONDS=120

# USB IDs claimed by the 8192eu module built from $COMMIT.
SUPPORTED_IDS="0bda:818b 0bda:818c 2001:3312 2001:3319 2019:ab33 2357:0107 2357:0108 2357:0109 2357:0126 2c4e:0100 2c4e:0104"

log() { echo "[${NAME}] $*"; }
die() { echo "[${NAME}] error: $*" >&2; exit 1; }

stick_present() {
  local id
  for id in $SUPPORTED_IDS; do
    lsusb -d "$id" >/dev/null 2>&1 && { echo "$id"; return 0; }
  done
  return 1
}

# Network interface currently bound to the 8192eu driver, if any.
stick_interface() {
  local dev
  for dev in /sys/bus/usb/drivers/rtl8192eu/*/net/*; do
    [ -e "$dev" ] && { basename "$dev"; return 0; }
  done
  return 1
}

# True when the stick's own interface can reach its default gateway.
stick_online() {
  local iface gw
  iface=$(stick_interface) || return 1
  gw=$(ip -4 route show default dev "$iface" 2>/dev/null | awk '{print $3; exit}')
  [ -n "$gw" ] && ping -c1 -W3 -I "$iface" "$gw" >/dev/null 2>&1
}

use_rtl8xxxu() {
  rm -f "$BLACKLIST_CONF"
  modprobe -r 8192eu 2>/dev/null || true
  modprobe rtl8xxxu 2>/dev/null || true
}

platform_flag() {
  case "$(uname -m)" in
    armv6l | armv7l) echo ARM_RPI ;;
    aarch64) echo ARM_AARCH64 ;;
    x86_64 | i686) echo I386_PC ;;
    *) die "unsupported architecture $(uname -m)" ;;
  esac
}

headers_package() {
  local release flavor
  release=$(uname -r)
  if dpkg -s raspberrypi-kernel-headers >/dev/null 2>&1; then
    echo raspberrypi-kernel-headers
    return
  fi
  # Raspberry Pi OS bookworm and later: track the meta package so DKMS has
  # headers for every future kernel, not only the running one.
  if [[ "$release" == *+rpt-* ]]; then
    flavor=${release##*+rpt-}
    if apt-cache show "linux-headers-${flavor}" >/dev/null 2>&1; then
      echo "linux-headers-${flavor}"
      return
    fi
  fi
  echo "linux-headers-${release}"
}

install_fallback() {
  cat > "$FALLBACK_BIN" <<'EOF'
#!/bin/sh
# Boot safety net from rtl8192eu-raspberrypi: if the Wi-Fi stick has no
# network 3 minutes after boot, drop the 8192eu driver and use rtl8xxxu again.
for i in $(seq 1 36); do
  for dev in /sys/bus/usb/drivers/rtl8192eu/*/net/*; do
    [ -e "$dev" ] || continue
    iface=$(basename "$dev")
    gw=$(ip -4 route show default dev "$iface" 2>/dev/null | awk '{print $3; exit}')
    [ -n "$gw" ] && ping -c1 -W3 -I "$iface" "$gw" >/dev/null 2>&1 && exit 0
  done
  sleep 5
done
echo "rtl8192eu: no network 3 minutes after boot, reverting to rtl8xxxu"
rm -f /etc/modprobe.d/blacklist-rtl8xxxu.conf
modprobe -r 8192eu 2>/dev/null
modprobe rtl8xxxu
EOF
  chmod 755 "$FALLBACK_BIN"
  cat > "$FALLBACK_UNIT" <<EOF
[Unit]
Description=Revert to rtl8xxxu if the RTL8192EU stick has no network after boot
After=NetworkManager.service network.target

[Service]
Type=oneshot
ExecStart=${FALLBACK_BIN}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable rtl8192eu-fallback.service >/dev/null 2>&1
}

remove_legacy_install() {
  # Earlier versions of this repository installed the module by hand.
  rm -f /lib/modules/*/updates/8192eu.ko
  if [ -f /etc/systemd/system/wifi-driver-fallback.service ] &&
    grep -q "rtl8xxxu" /etc/systemd/system/wifi-driver-fallback.service; then
    systemctl disable wifi-driver-fallback.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/wifi-driver-fallback.service /usr/local/bin/wifi-driver-fallback.sh
  fi
}

do_status() {
  local iface driver
  echo "stick:        $(stick_present || echo 'not found')"
  for iface in /sys/class/net/*; do
    driver=$(basename "$(readlink "$iface/device/driver" 2>/dev/null)" 2>/dev/null || true)
    case "$driver" in rtl8192eu | rtl8xxxu) echo "interface:    $(basename "$iface") (driver ${driver})" ;; esac
  done
  echo "dkms:         $(dkms status "${NAME}/${VERSION}" 2>/dev/null || echo 'not installed')"
  echo "rtl8xxxu:     $([ -f "$BLACKLIST_CONF" ] && echo blacklisted || echo allowed)"
  echo "boot fallback: $(systemctl is-enabled rtl8192eu-fallback.service 2>/dev/null || echo 'not installed')"
}

do_uninstall() {
  log "Removing the driver and returning to rtl8xxxu"
  systemctl disable rtl8192eu-fallback.service >/dev/null 2>&1 || true
  rm -f "$FALLBACK_UNIT" "$FALLBACK_BIN" "$OPTIONS_CONF"
  remove_legacy_install
  dkms remove "${NAME}/${VERSION}" --all >/dev/null 2>&1 || true
  rm -rf "$SRC"
  depmod -a
  systemctl daemon-reload
  use_rtl8xxxu
  log "Done"
}

do_install() {
  local id flag pkg iface i
  id=$(stick_present) || die "no supported Wi-Fi stick found (supported IDs: ${SUPPORTED_IDS})"
  flag=$(platform_flag)
  pkg=$(headers_package)
  log "Found stick ${id}; building for ${flag} on kernel $(uname -r)"

  log "Installing build tools and ${pkg}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq git build-essential dkms bc "$pkg" >/dev/null

  log "Fetching driver source at ${COMMIT:0:12}"
  dkms remove "${NAME}/${VERSION}" --all >/dev/null 2>&1 || true
  rm -rf "$SRC"
  git clone -q "$UPSTREAM" "$SRC"
  git -C "$SRC" -c advice.detachedHead=false checkout -q "$COMMIT"
  sed -i -E 's/^(CONFIG_PLATFORM_(I386_PC|ARM_RPI|ARM_AARCH64)) = y/\1 = n/' "$SRC/Makefile"
  sed -i -E "s/^(CONFIG_PLATFORM_${flag}) = n/\1 = y/" "$SRC/Makefile"

  log "Building with DKMS (20-40 minutes on a Pi 2, a few minutes on a Pi 4)"
  dkms add -m "$NAME" -v "$VERSION" >/dev/null
  dkms build -m "$NAME" -v "$VERSION"
  dkms install -m "$NAME" -v "$VERSION" --force >/dev/null
  remove_legacy_install
  depmod -a
  echo "options 8192eu rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0" > "$OPTIONS_CONF"

  log "Trial: switching the stick to 8192eu (Wi-Fi drops for up to ${TRIAL_SECONDS} s)"
  modprobe -r rtl8xxxu 2>/dev/null || true
  modprobe -r 8192eu 2>/dev/null || true
  sleep 2
  modprobe 8192eu
  for i in $(seq 1 $((TRIAL_SECONDS / 5))); do
    sleep 5
    if stick_online; then
      iface=$(stick_interface)
      echo "blacklist rtl8xxxu" > "$BLACKLIST_CONF"
      install_fallback
      log "Success: ${iface} is online with 8192eu after $((i * 5)) s; installed permanently"
      log "Kernel updates rebuild the driver automatically through DKMS"
      return 0
    fi
  done

  log "No network with 8192eu after ${TRIAL_SECONDS} s; rolling back to rtl8xxxu"
  use_rtl8xxxu
  dkms remove "${NAME}/${VERSION}" --all >/dev/null 2>&1 || true
  rm -f "$OPTIONS_CONF"
  die "trial failed; the system is back on rtl8xxxu"
}

[ "$(id -u)" -eq 0 ] || exec sudo -- "$0" "$@"

case "${1:-}" in
  --status) do_status ;;
  --uninstall) do_uninstall ;;
  --foreground) do_install ;;
  "")
    # Run detached: switching the Wi-Fi driver can drop an SSH session, and
    # the install must still finish (or roll back) on its own.
    if systemctl is-active --quiet "$UNIT"; then
      die "an install is already running; follow it with: journalctl -fu ${UNIT}"
    fi
    systemd-run --unit="$UNIT" --collect --quiet /bin/bash "$(readlink -f "$0")" --foreground
    log "Installing in the background. Follow progress with:"
    log "  journalctl -fu ${UNIT}"
    ;;
  *) die "unknown option ${1}; use --status, --uninstall or --foreground" ;;
esac
