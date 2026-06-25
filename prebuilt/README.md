# Prebuilt Kernel Directory

Place the prebuilt kernel file here:

- **kernel** - The kernel image for OnePlus Ace 5 Racing Edition (PLF110)

## How to get the kernel

1. Download from OnePlus kernel source: https://github.com/OnePlusOSS
2. Or extract from a stock ROM dump
3. The kernel should be for MediaTek Dimensity 9400e (MT6991) platform

## Kernel format

The kernel should be named `kernel` (without extension) and placed in this directory.

## Building from source

If you want to build the kernel from source:

```bash
# Clone kernel source
git clone https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991.git kernel

# Build kernel
cd kernel
make mt6991_defconfig
make -j$(nproc)

# Copy kernel to prebuilt
cp out/arch/arm64/boot/Image.gz prebuilt/kernel
```
