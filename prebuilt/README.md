# Prebuilt files

These files are extracted from the stock OnePlus Ace 5 Ultra (PLC110)
Android 16 firmware. They are not committed because they are large
proprietary binaries.

| File | Source | Purpose |
|------|--------|---------|
| `kernel` | `boot_b.img` | Stock GKI 6.6 kernel (LZ4 compressed). Only used if a boot image is built. |
| `dtb` | `vendor_boot_b.img` | Stock DTB (540944 bytes), embedded into the TWRP `vendor_boot.img`. |
| `vendor_ramdisk00.cpio.lz4` | `vendor_boot_b.img` | Stock PLATFORM vendor ramdisk (type 0x1). Kept so normal boot still works and TWRP gets the stock first-stage init, fstab and 319 kernel modules. |

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

The scripts use AOSP `unpack_bootimg.py` and write the three files into this
directory. `build.sh` runs the extraction automatically when a file is
missing.

## Notes

* The stock `vendor_boot.img` contains two vendor ramdisk fragments:
  `vendor_ramdisk00` (type 0x1 PLATFORM) and `vendor_ramdisk01`
  (type 0x2 RECOVERY, name `recovery`).
* TWRP is built as the 0x2 RECOVERY fragment. The 0x1 fragment must stay the
  factory one, because it carries the UFS/display/touch modules and the
  first-stage init needed for both normal boot and recovery.
* If a firmware update changes `vendor_ramdisk00`, regenerate the prebuilts.