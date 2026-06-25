# TWRP Device Tree for OnePlus Ace 5 Racing Edition (PLF110)

## Spec Sheet

| Feature | Specification |
|---------|---------------|
| CPU | 1x Cortex-X4 @ 3.4GHz + 3x Cortex-A720 @ 2.85GHz + 4x Cortex-A520 @ 2.0GHz |
| Chipset | MediaTek Dimensity 9400e (MT6991) |
| GPU | Mali-G925-Immortalis MC12 |
| Memory | 8GB / 12GB / 16GB LPDDR5X |
| Kernel | Linux 6.6 (GKI) |
| Shipped Software | Android 14, ColorOS 14 |
| Storage | 256GB / 512GB UFS 4.0 |
| Battery | 6400 mAh (typical) |
| Display | 6.78 inches, 1.5K AMOLED, 120Hz |
| Rear Camera | 50 MP (main) + 8 MP (ultrawide) + 2 MP (macro) |
| Front Camera | 16 MP |
| Release Date | 2025 |

## Source Code Repositories

### Official OnePlusOSS Repos (MT6991 Platform)

| Repository | Description | Branch |
|------------|-------------|--------|
| [OnePlusOSS/android_kernel_oneplus_mt6991](https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991) | Kernel source (Linux 6.6 GKI) | `oneplus/mt6991_b_16.0.0_oneplus_ace5_ultra` |
| [OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_mt6991](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_mt6991) | Vendor modules + device tree | `oneplus/mt6991_b_16.0.0_oneplus_ace5_ultra` |

### Note

PLF110 (Ace 5 Racing Edition) shares the same MT6991 platform with Ace 5 Ultra. The kernel source and vendor modules are identical; the device is differentiated by its project number in the DTS (oplus_project).

## Key Files in Vendor Source

| Path | Description |
|------|-------------|
| `vendor/oplus/kernel/boot/oplus_projectinfo/mtk/oplus_project.c` | Device project identification |
| `vendor/oplus/kernel/touchpanel/` | Touch panel drivers (goodix, focaltech, synaptics) |
| `vendor/oplus/kernel/vibrator/aw8697_haptic/` | Haptic feedback driver |
| `vendor/oplus/kernel/charger/` | Charging driver |
| `vendor/oplus/kernel/tp/hbp/hbp/` | Touch panel HBP framework |
| `vendor/oplus/kernel_device_modules-6.6/drivers/gpu/drm/oplus/oplus_panel/` | Display panel drivers |
| `vendor/mediatek/kernel_modules/` | MediaTek kernel modules (GPU, camera, connectivity) |
| `vendor/oplus/secure/biometrics/fingerprints/` | Fingerprint drivers |

## Building TWRP

### Prerequisites

- Ubuntu 20.04/22.04 LTS
- ~300GB free disk space
- Git, Python 3, and other build dependencies

### Build Instructions

1. Initialize the TWRP repo:
```bash
mkdir twrp && cd twrp
repo init -u https://github.com/nictas/android.git -b android-12.1
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

2. Clone this device tree:
```bash
git clone https://github.com/YOUR_USERNAME/device_oneplus_PLF110-TWRP.git device/oneplus/PLF110
```

3. Build kernel from OnePlusOSS source:
```bash
# Clone kernel source
git clone https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991.git -b oneplus/mt6991_b_16.0.0_oneplus_ace5_ultra kernel

# Build kernel (GKI)
cd kernel
make ARCH=arm64 gki_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# Copy kernel to prebuilt
cp out/arch/arm64/boot/Image.gz ../device/oneplus/PLF110/prebuilt/kernel
```

4. Build TWRP:
```bash
cd ~/twrp
source build/envsetup.sh
lunch twrp_PLF110-user
mka recoveryimage
```

5. The recovery image will be at:
```
out/target/product/PLF110/recovery.img
```

## Flashing Instructions

1. Boot into fastboot mode:
```bash
adb reboot bootloader
```

2. Flash recovery:
```bash
fastboot flash recovery recovery.img
```

3. Reboot to recovery:
```bash
fastboot reboot recovery
```

## Notes

- This is a WIP (Work In Progress) device tree
- Based on MediaTek Dimensity 9400e (MT6991) platform
- Uses GKI (Generic Kernel Image) architecture with kernel 6.6
- UFS partition path: `/dev/block/platform/11270000.ufshc/by-name/`
- The kernel uses `gki_defconfig` - standard GKI configuration
- Partition layout may need adjustment based on actual device dump
- Device is identified by project number in DTS `oplus_project` node

## Credits

- TWRP Team
- MediaTek for platform support
- OnePlus for kernel source (OnePlusOSS)
- Community contributors

## Links

- [TWRP Official](https://twrp.me)
- [TWRP Source](https://github.com/nictas/android)
- [OnePlusOSS MT6991 Kernel](https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991)
- [OnePlusOSS MT6991 Devicetree](https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_mt6991)
- [MediaTek Source](https://github.com/mediatek)
