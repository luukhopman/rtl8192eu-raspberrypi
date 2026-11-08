#!/bin/sh
# Trial the rtl8192eu driver with automatic fallback to rtl8xxxu.
# Nothing is made permanent: a reboot always returns to the old driver.
KO=/home/pi/wifi-driver/rtl8192eu-linux-driver/8192eu.ko
[ -f "$KO" ] || { echo "driver not built yet: $KO missing"; exit 1; }
sudo systemd-run --unit=wifi-driver-trial --no-block sh -c "
LOG=/var/log/pi-health.log
log() { echo \"\$(date -Is) driver-trial: \$*\" >> \$LOG; }
log \"switching rtl8xxxu -> rtl8192eu\"
modprobe -r rtl8xxxu
sleep 2
insmod $KO rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0 || log \"insmod failed\"
ok=0
for i in \$(seq 1 24); do
  sleep 5
  GW=\$(ip route show default 2>/dev/null | awk \"{print \\\$3; exit}\")
  if [ -n \"\$GW\" ] && ping -c1 -W3 \"\$GW\" >/dev/null 2>&1; then ok=1; break; fi
done
if [ \$ok = 1 ]; then
  log \"rtl8192eu connected after \$((i*5))s, keeping it (until reboot)\"
else
  log \"rtl8192eu no connection after 120s, falling back to rtl8xxxu\"
  rmmod 8192eu 2>/dev/null
  sleep 2
  modprobe rtl8xxxu
fi
"
echo "Trial started. The Wi-Fi drops for up to 2 minutes; the Pi falls back by itself if the new driver fails."
