#!/bin/bash
#
# Build and install the iBridge (touch bar / ALS) modules via DKMS, plus the
# modprobe and udev configuration the T1 needs in order to work at boot.
#
# Usage:  sudo ./install.sh [kernel-version]
#
# Defaults to the running kernel. Safe to re-run.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG=applespi
VER=0.1
KV="${1:-$(uname -r)}"
DEST="/usr/src/$PKG-$VER"

[ "$(id -u)" -eq 0 ] || { echo "error: must be run as root" >&2; exit 1; }

if [ ! -d "/lib/modules/$KV/build" ]; then
    echo "error: no kernel headers for $KV (/lib/modules/$KV/build missing)" >&2
    echo "       install the matching -headers package first" >&2
    exit 1
fi

echo "==> Installing sources to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
for f in Makefile dkms.conf applespi.c applespi.h applespi_trace.h \
         apple-ibridge.c apple-ibridge.h apple-ib-tb.c apple-ib-als.c; do
    cp "$SRC/$f" "$DEST/"
done

echo "==> Removing any hand-installed copies that would shadow the DKMS build"
for d in /lib/modules/*/updates; do
    for m in apple-ibridge apple-ib-tb apple-ib-als; do
        rm -f "$d/$m.ko" "$d/$m.ko.zst"
    done
done

echo "==> Building via DKMS for $KV"
dkms remove  "$PKG/$VER" -k "$KV" >/dev/null 2>&1 || true
dkms add     "$PKG/$VER" >/dev/null 2>&1 || true
dkms build   "$PKG/$VER" -k "$KV"
dkms install "$PKG/$VER" -k "$KV" --force

echo "==> Installing configuration"
install -Dm644 "$SRC/apple-ibridge.modprobe.conf" /etc/modprobe.d/apple-ibridge.conf
install -Dm644 "$SRC/apple-ibridge.udev.rules"    /etc/udev/rules.d/60-apple-ibridge.rules
udevadm control --reload-rules || true

echo "==> Running depmod"
depmod -a "$KV"

echo
echo "Done. Reboot, then verify with:"
echo "  cat /sys/bus/usb/devices/1-3/bConfigurationValue     # expect 1"
echo "  lsmod | grep -E 'apple_ib|hid_sensor'                # apple_ib_*, no hid_sensor_*"
