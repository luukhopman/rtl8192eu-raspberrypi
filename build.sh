#!/bin/sh
# Build the rtl8192eu driver (Mange) for this Pi. Only builds; does not install or load it.
set -e
cd ~/wifi-driver/rtl8192eu-linux-driver
sed -i "s/^CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/; s/^CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/" Makefile
systemd-run --user --unit=rtl-build --no-block sh -c "cd ~/wifi-driver/rtl8192eu-linux-driver && nice make -j3 ARCH=arm KSRC=/lib/modules/\$(uname -r)/build > ~/wifi-driver/build.log 2>&1; echo EXIT=\$? >> ~/wifi-driver/build.log"
echo "Build started in the background on the Pi."
