# Use the device's real, factory PLATFORM vendor ramdisk (vendor_boot table
# entry type 0x1) instead of the one this build generates.
#
# The bootloader loads the 0x1 fragment by itself for a normal Android boot
# and concatenates it with the 0x2 RECOVERY fragment only when booting
# recovery.  The factory fragment carries the complete first-stage rootfs
# (init, linkerconfig, sepolicy, fstab and 319 kernel modules), which cannot
# be regenerated from the TWRP manifest.  Keeping it therefore preserves
# normal boot and gives TWRP all the display/touch/UFS modules it needs.
#
# build/make/core/Makefile always generates the PLATFORM ramdisk itself and
# passes it as --vendor_ramdisk; BOARD_VENDOR_RAMDISK_FRAGMENT.*.PREBUILT
# only covers extra fragments.  Reassigning INTERNAL_VENDOR_RAMDISK_TARGET
# here works because this file is pulled in at the very end of core/Makefile
# and make expands recipe bodies at execution time.
#
# The RECOVERY (0x2) fragment is still built from this tree's TWRP sources on
# every compile.  Regenerate the prebuilt with tools/extract-prebuilts.sh if
# it is missing or if the stock firmware is updated.

ifeq ($(TARGET_DEVICE),PLC110)

PLC110_PREBUILT_VENDOR_RAMDISK := device/oneplus/PLC110/prebuilt/vendor_ramdisk00.cpio.lz4

ifeq ($(wildcard $(PLC110_PREBUILT_VENDOR_RAMDISK)),)
$(error Missing $(PLC110_PREBUILT_VENDOR_RAMDISK); run tools/extract-prebuilts.sh with a stock vendor_boot.img first)
endif
ifeq ($(wildcard $(TARGET_PREBUILT_DTB)),)
$(error Missing $(TARGET_PREBUILT_DTB); run tools/extract-prebuilts.sh with a stock vendor_boot.img first)
endif

$(INSTALLED_VENDOR_BOOTIMAGE_TARGET): $(PLC110_PREBUILT_VENDOR_RAMDISK)
$(INSTALLED_VENDOR_BOOTIMAGE_TARGET): $(TARGET_PREBUILT_DTB)

INTERNAL_VENDOR_RAMDISK_TARGET := $(PLC110_PREBUILT_VENDOR_RAMDISK)

endif