# GMKtec NucBox G3 Hardware Watchdog on Proxmox VE

A tested configuration for enabling the **Intel OC hardware watchdog** on a GMKtec NucBox G3 running Proxmox VE.

The important result is:

```text
systemd -> /dev/watchdog0 -> intel_oc_wdt -> Intel OC_WDT -> hardware reset
```

This setup was validated by deliberately letting the watchdog expire and confirming that the machine performed a hardware reboot.

## Tested platform

- **System:** GMKtec NucBox G3
- **CPU:** Intel Processor N100 / Alder Lake-N
- **BIOS:** `GMK_G3`
- **BIOS date:** 2023-10-21
- **OS:** Proxmox VE
- **Tested kernel:** `7.0.14-14-pve`
- **Watchdog driver:** `intel_oc_wdt`
- **Runtime watchdog timeout:** 30 seconds

## Why not `iTCO_wdt`?

The platform exposes an Intel TCO watchdog and the Linux `iTCO_wdt` driver can bind to it, but on this GMKtec G3 the TCO countdown did not actually progress.

During testing:

- `iTCO_wdt` loaded successfully;
- `/dev/watchdog0` was created;
- the driver reported a valid timeout;
- opening the watchdog cleared the TCO halt bit;
- nevertheless, the hardware countdown remained stuck and no watchdog reset occurred.

The firmware also programs and locks parts of the TCO/SMI configuration before Linux starts.

The useful watchdog on this platform is the separate **Intel OC Watchdog**, exposed by the kernel as:

```text
intel_oc_wdt
```

A direct hardware test confirmed that this watchdog resets the machine when its timer expires.

## Check driver availability

Recent Proxmox kernels already contain the driver:

```bash
modinfo intel_oc_wdt
```

Expected output includes:

```text
description:    Intel OC Watchdog driver
alias:          acpi*:INTC1099:*
alias:          acpi*:INT3F0D:*
```

## Proxmox kernel blacklist

Proxmox kernel packages may ship files such as:

```text
/usr/lib/modprobe.d/blacklist_proxmox-kernel-<kernel>.conf
```

which contain:

```text
blacklist intel_oc_wdt
```

Because files in `/etc/modprobe.d` have higher configuration priority, this project installs a kernel post-install hook that creates a local copy of each Proxmox blacklist file and removes only the `intel_oc_wdt` blacklist entry.

This makes the configuration survive future Proxmox kernel upgrades.

The `iTCO_wdt` blacklist is intentionally left untouched.

## Installation

Clone the repository and run:

```bash
git clone https://github.com/pi4-dev/gmktec-g3-watchdog.git
cd gmktec-g3-watchdog
sudo ./install.sh
```

Then reboot:

```bash
sudo reboot
```

## Installed configuration

### 1. Load the driver at boot

`/etc/modules-load.d/intel-oc-watchdog.conf`

```text
intel_oc_wdt
```

### 2. Enable the systemd hardware watchdog

`/etc/systemd/system.conf.d/watchdog.conf`

```ini
[Manager]
RuntimeWatchdogSec=30s
```

With a 30 second hardware timeout, systemd periodically refreshes the watchdog before the timer expires. If PID 1 or the system becomes unable to refresh it, the hardware watchdog resets the machine.

### 3. Survive Proxmox kernel upgrades

The following hook is installed:

```text
/etc/kernel/postinst.d/00-enable-intel-oc-wdt
```

For every Proxmox kernel blacklist file it:

1. copies the vendor configuration from `/usr/lib/modprobe.d` to `/etc/modprobe.d` when needed;
2. removes only the `blacklist intel_oc_wdt` line;
3. leaves other Proxmox blacklist entries intact.

## Verification

After reboot:

```bash
lsmod | grep intel_oc_wdt
```

Expected:

```text
intel_oc_wdt ...
```

Check the watchdog device:

```bash
wdctl /dev/watchdog0
```

Expected result:

```text
Device:        /dev/watchdog0
Identity:      intel_oc_wdt [version 0]
Timeout:       30 seconds
```

Check whether systemd has armed it:

```bash
cat /sys/class/watchdog/watchdog0/state
```

Expected:

```text
active
```

Check systemd configuration:

```bash
systemctl show --property=RuntimeWatchdogUSec
```

Expected:

```text
RuntimeWatchdogUSec=30s
```

Observe the live hardware countdown:

```bash
watch -n 1 cat /sys/class/watchdog/watchdog0/timeleft
```

The value should decrease and then periodically jump back up as systemd refreshes the watchdog.

## Confirmed hardware reset test

> **Warning:** This intentionally reboots the host. Stop or migrate workloads first.

For a controlled test, load the driver with a short timeout:

```bash
sudo modprobe -r intel_oc_wdt
sudo modprobe intel_oc_wdt heartbeat=5
```

Then open the watchdog without sending keepalives:

```bash
sudo python3 - <<'PY'
import os
import time

fd = os.open("/dev/watchdog0", os.O_WRONLY)
print("Watchdog opened; expecting hardware reset in about 5 seconds", flush=True)
time.sleep(10)
print("NO RESET", flush=True)
os.close(fd)
PY
```

On the tested GMKtec G3, this caused a hardware reboot after approximately five seconds.

After the test, reboot normally so the persistent 30 second systemd configuration is restored.

## Troubleshooting

### `intel_oc_wdt` does not load after reboot

Check:

```bash
journalctl -b -u systemd-modules-load --no-pager
```

If you see:

```text
Module 'intel_oc_wdt' is deny-listed (by kmod)
```

verify the local Proxmox blacklist overrides:

```bash
grep -Rni 'intel_oc_wdt' /etc/modprobe.d /usr/lib/modprobe.d
```

The vendor file in `/usr/lib/modprobe.d` may still contain the blacklist entry. The corresponding local file under `/etc/modprobe.d` should not.

Re-run:

```bash
sudo /etc/kernel/postinst.d/00-enable-intel-oc-wdt
sudo modprobe intel_oc_wdt
```

### Watchdog is present but inactive

Check:

```bash
systemctl show --property=RuntimeWatchdogUSec
cat /sys/class/watchdog/watchdog0/state
```

If `RuntimeWatchdogUSec=0`, verify:

```text
/etc/systemd/system.conf.d/watchdog.conf
```

and run:

```bash
sudo systemctl daemon-reexec
```

## Files in this repository

```text
.
├── README.md
├── install.sh
├── config
│   ├── intel-oc-watchdog.conf
│   └── watchdog.conf
└── hooks
    └── 00-enable-intel-oc-wdt
```

## Notes

- This configuration intentionally uses `intel_oc_wdt`, not `iTCO_wdt`.
- `nowayout` is left at its default value.
- A 30 second timeout was selected for the tested Proxmox host.
- The kernel driver exposes the normal Linux watchdog API, so no custom daemon is required; systemd is the watchdog client.
- Verify behaviour on your own hardware before relying on the watchdog for unattended recovery.
