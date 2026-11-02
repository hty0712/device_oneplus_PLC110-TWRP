# Prebuilt files

These files are extracted from the stock OnePlus Ace 5 Ultra (PLC110)
Android 16 firmware. They are not committed because they are large
proprietary binaries.

| Path | Source | Purpose |
|------|--------|---------|
| `kernel` | `boot_b.img` | Stock GKI 6.6 kernel (LZ4 compressed). Only used if a boot image is built. |
| `dtb` | `vendor_boot_b.img` | Stock DTB (540944 bytes), embedded into the TWRP `vendor_boot.img`. |
| `ramdisk/first_stage_ramdisk/` | `vendor_boot_b.img`, PLATFORM ramdisk `first_stage_ramdisk` | `fstab.mt6991`. First stage init needs it to mount the dynamic partitions, i.e. without it a normal power-on cannot boot Android at all. |
| `ramdisk/lib/modules/` | `vendor_boot_b.img`, PLATFORM ramdisk `lib/modules` | 319 stock kernel modules plus `modules.load`, `modules.load.recovery`, `modules.dep`, `modules.alias` and `modules.softdep`. |
| `ramdisk/vendor/firmware/` | `vendor_boot_b.img`, PLATFORM ramdisk `vendor/firmware` | Touch firmware, requested while the touch driver probes. |

## Generate them

From a connected, rooted device:

```bash
./tools/extract-prebuilts.sh --from-device
```

From stock images:

```bash
./tools/extract-prebuilts.sh --boot boot.img --vendor-boot vendor_boot.img
```

Or let the script download the matching stock images:

```bash
./tools/extract-prebuilts.sh --download
```

On Windows:

```powershell
.\tools\extract-prebuilts.ps1
```

The scripts use AOSP `unpack_bootimg.py` and `extract_ramdisk_files.py` and
write the files into this directory. `build.sh` runs the extraction
automatically when a file is missing.

## Notes

* The stock `vendor_boot.img` contains two vendor ramdisk fragments:
  `vendor_ramdisk00` (type 0x1 PLATFORM) and `vendor_ramdisk01`
  (type 0x2 RECOVERY, name `recovery`).
* Both of them have to exist in the TWRP image:
  * the bootloader only reads the 0x2 RECOVERY fragment in recovery mode, so
    TWRP lives there, and it asserts that such a fragment exists;
  * the 0x1 PLATFORM fragment is the vendor ramdisk a normal power-on uses.
    It is repacked from `prebuilt/ramdisk` here (16.3 MB) instead of using the
    factory one (40.4 MB), because the bootloader checks the `init_boot`
    ramdisk plus all vendor_boot fragments against a fixed 64 MiB initrd
    buffer.
* The factory PLATFORM ramdisk's `/system` tree (44 MB of factory test tools)
  and its `res`/`sepolicy` copies are dropped; nothing needs them.
* The recovery fragment no longer carries the modules or the firmware itself —
  in recovery mode both fragments are concatenated, so `/lib/modules` and
  `/vendor/firmware` from PLATFORM are already there.
* If a firmware update changes the kernel modules or the first stage fstab,
  regenerate the prebuilts.

