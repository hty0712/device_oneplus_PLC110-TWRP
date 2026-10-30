# TWRP 16 Device Tree for OnePlus Ace 5 Ultra (PLC110)

TWRP 3.7.1_16 device tree for the OnePlus Ace 5 Ultra (model **PLC110**,
stock product device **OP60EDL1**, internal codename **emira**), based on
MediaTek **MT6991** and Android 16.

The tree targets `TWRP-Test/platform_manifest_twrp_aosp` branch
**twrp-16.0** and builds a **vendor_boot.img** with a RECOVERY ramdisk
fragment. There is no recovery partition on this device.

## Spec sheet (read from the connected device)

| Feature | Value |
|---------|-------|
| Model | PLC110 (OnePlus Ace 5 Ultra, CN) |
| Stock product device | OP60EDL1 |
| SoC | MediaTek MT6991 (Dimensity 9400 series), arm64 only |
| RAM | 16 GB (`ro.boot.ddr_size=17179869184`) |
| Storage | 512 GB UFS 4.x (userdata 493040402432 bytes) |
| Display | 1272 x 2800, 560 dpi, 120 Hz, 141 px top cutout |
| Battery | 6700 mAh (`charge_full_design=6700000` uAh) |
| Kernel | GKI 6.6.118 (`6.6.118-android15-8-...-4k`) |
| Stock software | Android 16, `BP2A.250605.015`, `PLC110_16.0.10.500(CN01)` |
| Fingerprint | `OnePlus/PLC110/OP60EDL1:16/BP2A.250605.015/V.dff485_173d7fc_1705300:user/release-keys` |
| Touch | Synaptics TCM (`oplus_bsp_tp_tcm_S3910.ko`) |
| Partition scheme | A/B, virtual A/B with XOR compression, dynamic partitions group `main` |

## How recovery works on this device

The stock `vendor_boot.img` contains two vendor ramdisk fragments:

| Fragment | Type | Size | Contents |
|----------|------|------|----------|
| `vendor_ramdisk00` | `0x1` PLATFORM | 40368065 bytes | First-stage init, fstab and 319 MTK/OPlus kernel modules (UFS, display, touch, haptics, charger) |
| `vendor_ramdisk01` | `0x2` RECOVERY | 13936044 bytes | Stock ColorOS recovery ramdisk |

The bootloader loads the PLATFORM fragment by itself for a normal boot and
concatenates it with the RECOVERY fragment only when booting recovery.
Therefore:

* TWRP is built as the `0x2` RECOVERY fragment.
* The `0x1` PLATFORM fragment is kept byte-for-byte from stock
  (`prebuilt/vendor_ramdisk00.cpio.lz4`), so normal Android boot keeps working
  and TWRP gets all stock kernel modules for free.
* The image is flashed to **vendor_boot**, not to `boot` or `init_boot`.

`build/tasks/vendor_boot.mk` redirects AOSP's generated PLATFORM ramdisk to
the stock prebuilt while leaving the RECOVERY fragment built from TWRP
sources on every compile.

## Requirements

* Ubuntu 22.04/24.04 (or WSL2 with Ubuntu)
* ~250 GB free disk space
* OpenJDK 21 (Android 16)
* `repo`, `git`, `python3`, `curl`
* A rooted PLC110 via adb **or** the stock `boot.img` / `vendor_boot.img`
  (to generate the prebuilts)

## Build

```bash
chmod +x build.sh tools/extract-prebuilts.sh
./build.sh
```

The script:

1. `repo init -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-16.0`
2. copies this tree to `device/oneplus/PLC110`
3. extracts `prebuilt/kernel`, `prebuilt/dtb` and
   `prebuilt/vendor_ramdisk00.cpio.lz4` from a stock image or the connected
   device
4. runs `lunch twrp_PLC110-userdebug` and `mka vendorbootimage`

Output:

```
out/target/product/PLC110/vendor_boot.img
```

Manual build:

```bash
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch twrp_PLC110-userdebug
mka vendorbootimage
```

## Prebuilts

The three stock binaries are not committed (they are listed in `.gitignore`).

```bash
# from a rooted device
./tools/extract-prebuilts.sh --from-device

# from stock images
./tools/extract-prebuilts.sh --boot boot.img --vendor-boot vendor_boot.img

# download the matching stock images
./tools/extract-prebuilts.sh --download
```

Windows:

```powershell
.\tools\extract-prebuilts.ps1
```

`prebuilt/kernel` is only needed if a boot image is built; the vendor_boot
build uses `prebuilt/dtb` and `prebuilt/vendor_ramdisk00.cpio.lz4`.

## Flash

**Unlock the bootloader first.** Flashing a modified vendor_boot on a locked
bootloader is rejected.

Back up the stock vendor_boot of both slots (root required):

```bash
adb shell su -c "dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot_a.img"
adb shell su -c "dd if=/dev/block/by-name/vendor_boot_b of=/sdcard/vendor_boot_b.img"
adb pull /sdcard/vendor_boot_a.img
adb pull /sdcard/vendor_boot_b.img
```

Flash TWRP:

```bash
adb reboot bootloader
fastboot flash vendor_boot_a vendor_boot.img
fastboot flash vendor_boot_b vendor_boot.img
fastboot reboot recovery
```

If `fastboot reboot recovery` is not supported by the bootloader, power off
and use the hardware key combination (Volume Down + Power).

The image carries a self-signed AVB hash footer. On an unlocked bootloader it
boots as-is; if the bootloader still refuses it, flash a verity/verification
disabled vbmeta for your firmware before flashing the image.

Restore stock:

```bash
fastboot flash vendor_boot_a vendor_boot_a.img
fastboot flash vendor_boot_b vendor_boot_b.img
```

## Status / known limitations

Working (expected, based on the stock ramdisk contents and flags):

* Display (1272x2800, 120 Hz), touch, hardware keys
* ADB / MTP / sideload
* Mounting `/system`, `/vendor`, `/product`, `/odm` and all OPlus dynamic
  partitions
* Flashing images and zips, backup/restore of the boot images

Needs testing / extra work:

* **FBE decryption**: `TW_INCLUDE_CRYPTO` and FBE v2 are enabled, and
  `init.recovery.trustonic.rc` starts the stock Trustonic `mcDriverDaemon`,
  KeyMint 3.0 and Gatekeeper services when TWRP has `/vendor` and `/odm`
  mounted (`fstab.additional=1`). The factory PLATFORM ramdisk loads the TEE
  kernel modules. This is untested on hardware: if the decrypt screen times
  out, bundle the Trustonic binaries, libraries and `mcRegistry` TAs into
  `recovery/root/vendor/` and `recovery/root/odm/` (the tonga and Reno Z
  trees below document the exact file list and service setup).
* Fastbootd (the TWRP mock boot control HAL is used; slot switching depends
  on the vendor `IBootControl` service).
* Vibration uses the `aw8697` sysfs LED; no AIDL vibrator HAL is exposed.
* WiFi is not enabled (no firmware setup is included).

## Repository layout

```
BoardConfig.mk                     TWRP 16 board configuration (vendor_boot build)
twrp_PLC110.mk                     product makefile
device.mk                          product packages / virtual A/B
AndroidProducts.mk                 lunch choices
recovery.fstab                     fstab v2 for TWRP
recovery/root/system/etc/twrp.flags TWRP display/backup/flash flags
recovery/root/init.recovery.mt6991.rc USB controller / persist / keystore setup
recovery/root/init.recovery.usb.rc   configfs USB gadget (adb / MTP / fastbootd)
recovery/root/init.recovery.trustonic.rc stock TEE / KeyMint / Gatekeeper services
build/tasks/vendor_boot.mk         keep the stock PLATFORM ramdisk
prebuilt/                          kernel, dtb, stock PLATFORM ramdisk (generated)
tools/extract-prebuilts.*          stock image extraction helpers
```

## Notes

* Partition sizes and the dynamic-partition list were read from the device
  (`blockdev --getsize64`, `lpdump`): super `14680064000` bytes, group `main`
  `14675869696` bytes.
* The stock platform ramdisk loads the display, touch and haptics modules via
  `modules.load.recovery`, so `TW_LOAD_VENDOR_MODULES` is intentionally not
  set. Add it only for modules that are missing from the stock fragment.
* `TW_Y_OFFSET` / `TW_H_OFFSET` use the real 141 px cutout height reported by
  `dumpsys window displays`.
* `TW_CUSTOM_CPU_TEMP_PATH` points at `thermal_zone5` (`soc_max`). The zones
  on this kernel are: 5 `soc_max`, 21 `cpu-big-core7-0`, 45
  `slave_cp_temp` (the old value was the wrong zone).

## Credits

* TWRP team and the TWRP-Test manifest
* `kodeaqua/android_device_xiaomi_taiko-twrp` for the documented vendor_boot
  PLATFORM-fragment prebuilt technique
* OnePlusOSS kernel source: <https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991>
  (branch `oneplus/mt6991_b_16.0.0_oneplus_ace5_ultra`)

## Links

* [TWRP](https://twrp.me)
* [TWRP 16 manifest](https://github.com/TWRP-Test/platform_manifest_twrp_aosp)
* [OnePlusOSS MT6991 kernel](https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991)
* [MTK Trustonic crypto notes (tonga)](https://github.com/1ndevelopment/TWRP_tonga_device_tree/blob/main/docs/crypto-enable.md)
* [MTK Trustonic blob list (OPPO Reno Z)](https://github.com/danielpaul-123/twrp_oppo_renoz)