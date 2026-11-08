#!/bin/sh
# Make the rtl8192eu driver permanent, with a boot-time safety net back to rtl8xxxu.
set -e
KO=/home/pi/wifi-driver/rtl8192eu-linux-driver/8192eu.ko
[ -f "$KO" ] || { echo "driver not built: $KO missing"; exit 1; }
KV=$(uname -r)
sudo install -D -m 644 "$KO" /lib/modules/$KV/updates/8192eu.ko
sudo depmod -a
echo "options 8192eu rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0" | sudo tee /etc/modprobe.d/8192eu.conf >/dev/null
echo "blacklist rtl8xxxu" | sudo tee /etc/modprobe.d/blacklist-rtl8xxxu.conf >/dev/null
sudo tee /usr/local/bin/wifi-driver-fallback.sh >/dev/null <<"EOS"
#!/bin/sh
# At boot: if there is no network within 3 minutes, drop the rtl8192eu setup and use rtl8xxxu again.
LOG=/var/log/pi-health.log
for i in $(seq 1 36); do
  GW=$(ip route show default 2>/dev/null | awk "{print \$3; exit}")
  [ -n "$GW" ] && ping -c1 -W3 "$GW" >/dev/null 2>&1 && exit 0
  sleep 5
done
echo "$(date -Is) driver-fallback: no network 3 min after boot, reverting to rtl8xxxu" >> $LOG
rm -f /etc/modprobe.d/blacklist-rtl8xxxu.conf
rmmod 8192eu 2>/dev/null
modprobe rtl8xxxu
EOS
sudo chmod +x /usr/local/bin/wifi-driver-fallback.sh
sudo tee /etc/systemd/system/wifi-driver-fallback.service >/dev/null <<"EOS"
[Unit]
Description=Revert to rtl8xxxu if Wi-Fi is down after boot
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-driver-fallback.sh

[Install]
WantedBy=multi-user.target
EOS
sudo systemctl daemon-reload
sudo systemctl enable wifi-driver-fallback.service
echo "$(date -Is) driver-install: rtl8192eu installed for $KV, rtl8xxxu blacklisted" | sudo tee -a /var/log/pi-health.log >/dev/null
echo "Installed. The new driver is used from the next restart; a safety net reverts it if Wi-Fi fails at boot."
