# vendor_boot fragment layout for the OnePlus Ace 5 Ultra (PLC110, MT6991)
#
# The bootloader concatenates the init_boot ramdisk and the vendor_boot
# fragments into a single initrd and asserts the total against a fixed 64 MiB
# buffer (mb_ramdisk / LK_RAMDISK_SIZE, app/mt_boot/mt_boot.c), so both
# fragments have to be budgeted together:
#
#   init_boot ramdisk          3,757,180 B
#   PLATFORM  (0x1)            ~16,300,000 B   modules + firmware + first stage fstab
#   RECOVERY  (0x2)            ~41,500,000 B   TWRP itself
#                              ------------
#                              ~61,500,000 B   < 67,108,864 B
#
# Two fragments are required:
#
#   * LK only reads the 0x2 RECOVERY fragment in recovery mode, so TWRP lives
#     there.  The 0x1 PLATFORM fragment is what a normal power-on uses; while it
#     was an empty 4-byte stub Android could not boot at all, because first stage
#     found no /first_stage_ramdisk/fstab.mt6991 to mount the dynamic partitions
#     with.
#   * LK asserts that a 0x2 fragment exists when booting recovery
#     (boot_info.c: idx < entry_cnt), so TWRP cannot simply live in PLATFORM.
#
# The PLATFORM fragment is repacked here from prebuilt/ramdisk, which
# tools/extract-prebuilts.sh fills with the same files the factory PLATFORM
# ramdisk had (lib/modules, vendor/firmware and first_stage_ramdisk).  It is
# written with the LZ4 legacy frame the bootloader and kernel expect, and because
# the fragments end up as one continuous LZ4 stream the kernel decodes them back
# to back.
#
# The kernel modules are deliberately not copied into the recovery ramdisk: in
# recovery mode both fragments are concatenated, so /lib/modules from PLATFORM is
# already there (the stock recovery fragment relied on this too).

ifeq ($(TARGET_DEVICE),PLC110)

PLC110_PLATFORM_DIR := device/oneplus/PLC110/prebuilt/ramdisk
PLC110_PLATFORM_FILES := $(shell find $(PLC110_PLATFORM_DIR) -type f 2>/dev/null)

ifeq ($(strip $(PLC110_PLATFORM_FILES)),)
$(error Missing $(PLC110_PLATFORM_DIR); run tools/extract-prebuilts.sh with a stock vendor_boot.img first)
endif
ifeq ($(wildcard $(PLC110_PLATFORM_DIR)/lib/modules/modules.load),)
$(error Missing $(PLC110_PLATFORM_DIR)/lib/modules/modules.load; regenerate the prebuilts with tools/extract-prebuilts.sh)
endif
ifeq ($(wildcard $(PLC110_PLATFORM_DIR)/first_stage_ramdisk/fstab.mt6991),)
$(error Missing $(PLC110_PLATFORM_DIR)/first_stage_ramdisk/fstab.mt6991; normal boot needs it, regenerate the prebuilts with tools/extract-prebuilts.sh)
endif

# The PLATFORM (0x1) fragment: cpio packed with the LZ4 legacy frame
# (magic 02 21 4c 18) that mkbootfs + lz4 -l produce for the other fragments.
PLC110_PLATFORM_FRAGMENT := $(TARGET_RECOVERY_OUT)/plc110_platform_ramdisk.lz4

$(PLC110_PLATFORM_FRAGMENT): $(PLC110_PLATFORM_FILES) $(MKBOOTFS) $(LZ4)
	@mkdir -p $(dir $@)
	$(hide) $(MKBOOTFS) $(PLC110_PLATFORM_DIR) | $(abspath $(LZ4)) -l -12 --favor-decSpeed -q -c > $(abspath $@)

INTERNAL_VENDOR_RAMDISK_TARGET := $(PLC110_PLATFORM_FRAGMENT)
$(INSTALLED_VENDOR_BOOTIMAGE_TARGET): $(PLC110_PLATFORM_FRAGMENT)

endif
