#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this installer as root." >&2
    exit 1
fi

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

install -d -m 0755 /etc/modules-load.d
install -m 0644 "$ROOT_DIR/config/intel-oc-watchdog.conf"     /etc/modules-load.d/intel-oc-watchdog.conf

install -d -m 0755 /etc/systemd/system.conf.d
install -m 0644 "$ROOT_DIR/config/watchdog.conf"     /etc/systemd/system.conf.d/watchdog.conf

install -d -m 0755 /etc/kernel/postinst.d
install -m 0755 "$ROOT_DIR/hooks/00-enable-intel-oc-wdt"     /etc/kernel/postinst.d/00-enable-intel-oc-wdt

/etc/kernel/postinst.d/00-enable-intel-oc-wdt

modprobe intel_oc_wdt

systemctl daemon-reexec

echo
echo "intel_oc_wdt installed and systemd RuntimeWatchdogSec configured."
echo

if command -v wdctl >/dev/null 2>&1 && [ -e /dev/watchdog0 ]; then
    wdctl /dev/watchdog0 || true
else
    echo "Verify after reboot with: wdctl /dev/watchdog0"
fi

echo
echo "Recommended final step: reboot the host and verify:"
echo "  lsmod | grep intel_oc_wdt"
echo "  cat /sys/class/watchdog/watchdog0/state"
echo "  systemctl show --property=RuntimeWatchdogUSec"
