#
# Copyright (C) 2026 The TWRP Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

DEVICE_PATH := device/oneplus/PLC110

# Minimal manifest
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Architecture - MediaTek MT6991 (arm64 only)
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a55
TARGET_SUPPORTS_64_BIT_APPS := true

# Bootloader / platform
TARGET_BOOTLOADER_BOARD_NAME := mt6991
TARGET_BOARD_PLATFORM := mt6991
TARGET_NO_BOOTLOADER := true

# Kernel - stock GKI 6.6 boot.img kernel (header v4)
BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_IMAGE_NAME := kernel
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_BASE := 0x7fff8000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x26f08000
BOARD_KERNEL_TAGS_OFFSET := 0x07c88000
BOARD_DTB_OFFSET := 0x07c88000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=user
BOARD_RAMDISK_USE_LZ4 := true
BOARD_KERNEL_SEPARATED_DTBO := true
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
BOARD_MKBOOTIMG_ARGS += --board ""

# A/B (virtual A/B, no dedicated recovery partition)
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    vendor_boot \
    dtbo \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor \
    system \
    system_ext \
    product \
    vendor \
    odm \
    vendor_dlkm \
    odm_dlkm \
    system_dlkm \
    my_bigball \
    my_carrier \
    my_company \
    my_engineering \
    my_heytap \
    my_manifest \
    my_preload \
    my_product \
    my_region \
    my_stock

# Recovery is the 0x2 RECOVERY fragment of vendor_boot.
#
# The bootloader loads init_boot's ramdisk plus every vendor_boot fragment into
# one 64 MiB initrd buffer, so the factory PLATFORM ramdisk (40 MB) and the TWRP
# RECOVERY ramdisk cannot be shipped together.  The PLATFORM fragment is
# repacked from prebuilt/ramdisk instead (16 MB: first stage fstab, kernel
# modules and touch firmware), see build/tasks/recovery_ramdisk_files.mk; it is
# what a normal power-on boots with, while this RECOVERY fragment is only read in
# recovery mode.
#
# The 0x2 RECOVERY fragment is mandatory: when booting in recovery mode the
# bootloader looks it up in the fragment table and asserts
# (boot_info.c: "idx < entry_cnt") when it is missing, which is why TWRP has to
# stay a separate fragment instead of being merged into PLATFORM.
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
TARGET_NO_RECOVERY := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab

# Partitions (sizes read from the device with blockdev --getsize64)
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_FLASH_BLOCK_SIZE := 262144

# Dynamic partitions (liblp group is "main")
BOARD_SUPER_PARTITION_SIZE := 14680064000
BOARD_SUPER_PARTITION_GROUPS := main
BOARD_MAIN_SIZE := 14675869696
BOARD_MAIN_PARTITION_LIST := \
    system \
    system_ext \
    product \
    vendor \
    odm \
    vendor_dlkm \
    odm_dlkm \
    system_dlkm \
    my_product \
    my_engineering \
    my_company \
    my_carrier \
    my_region \
    my_heytap \
    my_stock \
    my_preload \
    my_bigball \
    my_manifest

# File systems
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true
# Keep the default TARGET_COPY_OUT_* for product/system_ext/odm/dlkm: setting
# them to 'product'/... requires BOARD_*IMAGE_FILE_SYSTEM_TYPE, which this
# recovery-only tree does not build.
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_SYSTEM := system

# Verified boot
BOARD_AVB_ENABLE := true

# Encryption (FBE v2 + metadata encryption, Trustonic KeyMint)
BOARD_USES_METADATA_PARTITION := true
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_USE_FSCRYPT_POLICY := 2
TW_INCLUDE_OMAPI := true

# KeyMint anti-rollback: must be >= the version that encrypted /data
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# Props
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Display - 1272x2800 panel, 141 px top cutout.
#
# TW_SCREEN_BLANK_ON_BOOT is deliberately not set: blanking and unblanking the
# MTK DRM pipeline right after the takeover commit makes this panel stop
# reporting vblank ("invalid vblank" spam + DPC runtime PM underflow) and the
# OPLUS exception handler resets the device a few seconds later.
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_SCREEN_WIDTH := 1272
TARGET_SCREEN_HEIGHT := 2800
TARGET_SCREEN_DENSITY := 560
TW_THEME := portrait_hdpi
TW_FRAMERATE := 120
TW_NO_SCREEN_BLANK := true
TW_Y_OFFSET := 141
TW_H_OFFSET := -141
TW_STATUS_ICONS_ALIGN := center
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
# leds-mtk exposes 1..4094 here (max_brightness / logic_max_brightness), while
# TWRP defaults TW_MAX_BRIGHTNESS to 255. Without this the slider saturates at
# 255, which the panel driver maps to ~6 % DBV - visibly dim even at 100 %.
TW_MAX_BRIGHTNESS := 4094
TW_DEFAULT_BRIGHTNESS := 1638

# No vibrator HAL is exposed on this device; aw8697 is driven through sysfs
TW_INPUT_BLACKLIST := "hbtp_vm"

# Misc
TW_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone5/temp"
TW_DEVICE_VERSION := PLC110-A16
TW_DEFAULT_LANGUAGE := zh_CN
TW_EXTRA_LANGUAGES := true
TW_EXCLUDE_APEX := true
TW_EXCLUDE_TWRPAPP := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_INCLUDE_FASTBOOTD := true
TW_INCLUDE_LPDUMP := true
TW_INCLUDE_LPTOOLS := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true
TW_USE_DMCTL := true
TW_USE_SERIALNO_PROPERTY_FOR_DEVICE_ID := true
TW_USE_TOOLBOX := true
TW_ENABLE_ALL_PARTITION_TOOLS := true

# File system tools
RECOVERY_SDCARD_ON_DATA := true
TARGET_USES_MKE2FS := true
TW_ENABLE_FS_COMPRESSION := true
TW_INCLUDE_FUSE_EXFAT := true
TW_INCLUDE_FUSE_NTFS := true
TW_INCLUDE_NTFS_3G := true
TW_NO_EXFAT_FUSE := true

# Props copied from vendor at runtime
TW_OVERRIDE_SYSTEM_PROPS := \
    "ro.build.product;ro.build.fingerprint=ro.vendor.build.fingerprint;ro.build.version.incremental"
TW_OVERRIDE_PROPS_ADDITIONAL_PARTITIONS := vendor

# Debug
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TARGET_RECOVERY_DEVICE_MODULES += debuggerd strace
RECOVERY_BINARY_SOURCE_FILES += \
    $(TARGET_OUT_EXECUTABLES)/debuggerd \
    $(TARGET_OUT_EXECUTABLES)/strace

# Extra libraries
TARGET_RECOVERY_DEVICE_MODULES += libion
TW_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so

# OTA assert (product device is OP60EDL1 in the stock build)
TARGET_OTA_ASSERT_DEVICE := PLC110,OP60EDL1,emira,oneplus_plc110