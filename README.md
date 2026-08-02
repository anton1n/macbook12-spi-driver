Input driver for the SPI keyboard / trackpad found on 12" MacBooks (2015 and later) and newer MacBook Pros (late 2016 through mid 2018), as well a simple touchbar and ambient-light-sensor driver for late 2016 MacBook Pro's and later.

The keyboard / trackpad driver here is now included in the kernel as of v5.3.

NOTE:
-----
The touchbar driver was refactored in late 2018; if you're upgrading from the `appletb` driver, please see the [Upgrading](#upgrading) section; if you're running a kernel before 4.16 then please check out the [legacy](../../tree/touchbar-driver-monolithic) branch instead.

Fork changes:
-------------
This fork updates the iBridge/touch bar side for current kernels. The `applespi`
keyboard/trackpad driver is unchanged (it has been in-tree since v5.3).

* **Builds on clang/LTO kernels.** The `Makefile` reads `CONFIG_CC_IS_CLANG`
  from the target kernel and switches to `LLVM=1` automatically, so distros
  that ship a clang-built kernel (CachyOS, Arch `linux-llvm`, …) no longer fail
  with `unrecognized command-line option '-mstack-alignment=8'`.
* **Touch bar survives suspend.** `apple-ib-tb` registered only
  `.reset_resume`, which the kernel calls solely when the USB device was reset
  during resume. Under s2idle the iBridge keeps its power and is never reset, so
  nothing undid the mode/display switch-off done at suspend and the touch bar
  stayed dark until reboot. It now registers `.resume` as well.
* **Ships the config the T1 needs at boot** — see
  [Touch bar setup](#touch-bar-setup-t1--ibridge) below. Without it the touch
  bar does not come up from a cold boot.
* `dkms.conf` builds for the kernel being installed (`$kernelver`) rather than
  the running one, so upgrades work.

Verified building against 6.18.40 (clang), 6.18.41 (gcc) and 7.1.5 (gcc);
runtime-tested on a MacBookPro14,3 on 6.18.40.

Quick install:
--------------
```
sudo ./install.sh              # or: sudo ./install.sh 6.18.41-1-lts
```
This installs the sources to `/usr/src/applespi-0.1`, builds and installs them
via DKMS, drops the two config files described below into `/etc`, and runs
`depmod`. It is safe to re-run. Reboot afterwards.

To build without installing:
```
make                           # toolchain is auto-detected
make KVERSION=6.18.41-1-lts    # build for a different kernel
```

Using it:
---------
If you're on any MacBook or MacBook Pro other than MacBook8,1 (2015), and you're running a kernel before 4.11, then you'll need to boot the kernel with `intremap=nosid`. In all cases make sure you don't have `noapic` in your kernel options.

On the 2015 MacBook you need to (re)compile your kernel with `CONFIG_X86_INTEL_LPSS=n` if running a kernel before 4.14. And on all kernels you need ensure the `spi_pxa2xx_platform` and `spi_pxa2xx_pci` modules are loaded too (if you don't have those module, rebuild your kernel with `CONFIG_SPI_PXA2XX=m` and `CONFIG_SPI_PXA2XX_PCI=m`).

On all other MacBook's and MacBook Pros you need to instead make sure both the `spi_pxa2xx_platform` and `intel_lpss_pci` modules are loaded (if these don't exist, you need to (re)compile your kernel with `CONFIG_SPI_PXA2XX=m` and `CONFIG_MFD_INTEL_LPSS_PCI=m`).

For best results everywhere, make sure all three modules (this `applespi` driver plus the two core ones mentioned above) are present in your initramfs/initrd so that the keyboard is functional by the time the prompt for the disk password appears. Also, having them loaded early also appears to remove the need for the `irqpoll` kernel parameter on MacBook8,1's.

Lastly, please see the [Keyboard/Touchpad/Touchbar](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7#keyboardtouchpadtouchbar) section of my gist for recommended user-space configurations and more details.

DKMS module (Debian & co):
--------------------------
As root, do the following (all MacBook's and MacBook Pro's except MacBook8,1 (2015)):
```
echo -e "\n# applespi\napplespi\nspi_pxa2xx_platform\nintel_lpss_pci" >> /etc/initramfs-tools/modules

apt install dkms
git clone https://github.com/roadrunner2/macbook12-spi-driver.git /usr/src/applespi-0.1
dkms install -m applespi -v 0.1
```

If you're on a MacBook8,1 (2015):
```
echo -e "\n# applespi\napplespi\nspi_pxa2xx_platform\nspi_pxa2xx_pci" >> /etc/initramfs-tools/modules

apt install dkms
git clone https://github.com/roadrunner2/macbook12-spi-driver.git /usr/src/applespi-0.1
dkms install -m applespi -v 0.1
```

Akmods module (RPM Fusion / Red Hat & co):
------------------------------------------
You can build the akmod package from this repository:

https://pagure.io/fedora-macbook12-spi-driver-kmod

Or use this [copr repository](https://copr.fedorainfracloud.org/coprs/meeuw/macbook12-spi-driver-kmod/):
```
$ dnf copr enable meeuw/macbook12-spi-driver-kmod

$ dnf install macbook12-spi-driver-kmod
```

What doesn't work:
------------------
* Autodetection of ISO layout
* Resume on MacBook8,1

Debugging:
----------
Packet tracing is exposed via the kernel tracepoints framework. Tracing of individual packet types can be enabled with something like the following:
```
echo 1 | sudo tee /sys/kernel/debug/tracing/events/applespi/applespi_keyboard_data/enable
```
The packets are then visible in `/sys/kernel/debug/tracing/trace`

Trackpad dimensions logging can be enabled with
```
echo 1 | sudo tee /sys/kernel/debug/applespi/enable_tp_dim
```
and then viewed with something like
```
sudo watch /sys/kernel/debug/applespi/tp_dim
```

Touchbar/ALS/iBridge:
---------------------
The touchbar and ambient-light-sensor (ALS) are part of the iBridge chip, and hence there are 3 modules corresponding to these (`apple_ibridge`, `apple_ib_tb`, and `apple_ib_als`). Generally loading any one of these will load the others, unless you are loading them via `insmod`. If loading manually (i.e. via `insmod`), you need to first load the `industrialio_triggered_buffer` module.

The touchbar driver provides basic touchbar functionality (enabling the touchbar and switching between modes based on the FN key). The touchbar is automatically dimmed and later switched off if no (internal) keyboard, touchpad, or touchbar input is received for a period of time; any (internal) keyboard, touchpad, or touchbar input switches it back on. The timeouts till the touchbar is dimmed and turned off can be changed via the `idle_timeout` and `dim_timeout` module params or sysfs attributes (`/sys/class/input/input9/device/...`); they default to 5 min and 4.5 min, respectively. See also `modinfo apple_ib_tb`.

The ALS driver exposes the ambient light sensor; if you have the `iio-sensor-proxy` installed then it should be recognized and handled automatically.

Touch bar setup (T1 / iBridge):
-------------------------------
On T1 machines (MacBookPro13,* and 14,*) two pieces of configuration are
required for the touch bar to work at boot. `install.sh` installs both; they are
kept in the repo as `apple-ibridge.modprobe.conf` and `apple-ibridge.udev.rules`.

**1. `/etc/modprobe.d/apple-ibridge.conf` — keep `hid-sensor-hub` away.**

The iBridge exposes two HID interfaces, and `apple-ib-tb` needs *both*: one
carries the touch bar **mode** field, the other the **display** on/dim/off field.
The HID core tags the second one `HID_GROUP_SENSOR_HUB`, so `hid-sensor-hub`
autoloads by modalias when the USB device enumerates — long before
`apple_ibridge` comes up via its `APP7777` ACPI device — and binds it first.
`apple-ib-tb` only activates once it has found both fields, so the result is a
touch bar that probes cleanly, registers its input device, and stays completely
black. Blacklisting the HID sensor stack lets `apple_ibridge` claim it. Nothing
is lost: `apple-ib-als` exposes the same sensor as an IIO device.

**2. `/etc/udev/rules.d/60-apple-ibridge.rules` — select USB configuration 1.**

The iBridge has three USB configurations and the driver needs config 1
(`APPLETB_BASIC_CONFIG`). When it comes up in another one, `appleib_hid_probe()`
calls `usb_driver_set_configuration()` from inside its own probe; that is
asynchronous, tears down every interface, drops the device to config 0, and only
then selects config 1. Run mid-boot, while udev is coldplugging and both HID
interfaces probe concurrently, this can leave the device stranded at config 0
with no interfaces at all. Setting the configuration from udev at `add` time
happens before any HID interface binds, so the driver's probe already sees
config 1 and never reconfigures the device itself.

If you want the touch bar always on and never dimmed:
```
echo 'options apple_ib_tb idle_timeout=-1 dim_timeout=-1' | sudo tee /etc/modprobe.d/apple-ib-tb.conf
```

### Troubleshooting

Verify the whole chain:
```
cat /sys/bus/usb/devices/1-3/bConfigurationValue    # expect: 1
for h in /sys/bus/hid/devices/*; do
    echo "$(basename $h) -> $(basename $(readlink $h/driver 2>/dev/null) 2>/dev/null)"
done                                                # both 05AC:8600 -> apple-ibridge-hid
lsmod | grep -E 'apple_ib|hid_sensor'               # apple_ib_*, and no hid_sensor_*
```

If only *one* `05AC:8600` device is bound to `apple-ibridge-hid`, the other was
stolen — check that the modprobe blacklist is in place. Note that `modprobe -R`
ignores blacklists and is not a valid test; use the alias directly:
```
modprobe -n -v 'hid:b0003g0003v000005ACp00008600'   # should print nothing
```

**Touch bar wedged (dark despite the driver reporting success).** If it has been
through a suspend without a matching resume, it can latch into an unresponsive
state that survives a module reload — the USB writes all succeed and no error is
logged, but the panel stays black. Force a full re-enumeration:
```
echo 0 | sudo tee /sys/bus/usb/devices/1-3/bConfigurationValue
sleep 2
echo 1 | sudo tee /sys/bus/usb/devices/1-3/bConfigurationValue
```
A reboot does the same. Worth knowing when testing suspend behaviour: starting
from a wedged state makes the result meaningless.

**Checking suspend/resume:**
```
sudo rtcwake -m mem -s 10
dmesg | grep -iE 'Touchbar (suspended|resumed)'     # must show BOTH halves
```

Upgrading:
----------
The touchbar and ALS drivers used to be in a single module, `appletb`. This has now been split up into 3 modules, `apple_ibridge`, `apple_ib_tb`, and `apple_ib_als`. Generally whereever you were using `appletb` (e.g. in the initrd/dracut/whatever configs) you want to use `apple_ib_tb` now. Also, make sure to remove the old `appletb` module, either by first doing a `sudo dkms remove applespi/0.1 --all` before upgrading, or by manually removing the driver (e.g. `sudo find /lib/modules/ -name appletb.ko | xargs rm`).

Some useful threads:
--------------------
* https://bugzilla.kernel.org/show_bug.cgi?id=108331
* https://bugzilla.kernel.org/show_bug.cgi?id=99891
* https://gist.github.com/almas/5f75adb61bccf604b6572f763ce63e3e (Ubuntu LTS on MacBook Pro 2017 (A1707, MBP 14,3))
