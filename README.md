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

The bootloader concatenates the `init_boot` ramdisk and the vendor_boot
fragments into a single initrd and asserts the total against a fixed 64 MiB
buffer (`mb_ramdisk` / `LK_RAMDISK_SIZE = 0x4000000`, see
`app/mt_boot/mt_boot.c`). With `init_boot` using 3.58 MB, everything in
`vendor_boot` has to fit in **63.35 MB**:

```
factory PLATFORM 40368065 + factory RECOVERY 13936044 = 54304109
   + init_boot 3757180 = 58061289 < 67108864   -> stock, fits

our PLATFORM 16300000 + TWRP RECOVERY 41500000 = 57800000
   + init_boot 3757180 = 61557180 < 67108864   -> fits (~5.3 MiB spare)
```

Both fragments are needed, and they carry different things:

* The `0x2` **RECOVERY** fragment is TWRP. The bootloader only reads it in
  recovery mode, and it asserts that it exists (`boot_info.c:
  idx < entry_cnt`) when booting recovery.
* The `0x1` **PLATFORM** fragment is what a normal power-on uses as the vendor
  ramdisk. It has to provide first stage init with
  `/first_stage_ramdisk/fstab.mt6991` and the kernel modules, otherwise the
  kernel cannot mount the dynamic partitions and Android never boots. While it
  was an empty 4-byte stub, *every* normal boot ended in a bootloop.

So the factory PLATFORM ramdisk is replaced by a much smaller one that is
repacked from `prebuilt/ramdisk`:

* `first_stage_ramdisk/fstab.mt6991` — the first stage fstab (normal boot)
* `lib/modules` — 319 `.ko` files plus `modules.load`,
  `modules.load.recovery`, `modules.dep`, `modules.alias`, `modules.softdep`;
  first stage init loads them exactly like in stock, in both boot modes
* `vendor/firmware` — the touch firmware, requested while the touch driver
  probes, i.e. before `/vendor` is mounted

The factory ramdisk's `/system` tree (44 MB of factory test tools) and its
`res`/`sepolicy` copies are dropped; nothing needs them. Because the recovery
fragment no longer has to carry the modules itself, TWRP stays well inside the
budget.

* The ramdisk **must stay LZ4 legacy**: the kernel picks the decompressor from
  the first initrd member, and the stock `init_boot` ramdisk is LZ4 (magic
  `0x184C2102`). Both fragments are written with the same frame, so the kernel
  decodes them back to back as one stream.
* The image is flashed to **vendor_boot**, not to `boot` or `init_boot`.
* Normal boot now works again, which also means the device is not locked into
  recovery: `twrp.flags`/`TwReboot` hand the boot back to the system.

`build/tasks/recovery_ramdisk_files.mk` repacks `prebuilt/ramdisk` into the
PLATFORM fragment on every compile.

### Entering recovery from the bootloader

The bootloader (LK) never selects recovery from a key press. MTK's `blxboot`
enters fastboot when its download key is held and OPPO's build runs
`vol_down_key_check()` for the same purpose, so a held Volume Down sets
`g_boot_mode = 99` (`FASTBOOT_BOOT`). `boot_mode_check()` only takes
`RECOVERY_BOOT` (2) from the `reboot,recovery` restart reason, i.e. the
`boot-recovery` command in `/misc` that `adb reboot recovery`, the TWRP reboot
menu and `fastboot reboot recovery` write. Bootloader log (`expdb`) from this
device:

```
# plain power-on
vol_down_key_check:197: vol_down_key_check gpio condition is 11   (printed twice)
boot_mode_check:g_boot_mode is set 0                                -> NORMAL_BOOT

# Volume Down held
vol_down_key_check:197: vol_down_key_check gpio condition is 11    (printed once)
boot_mode_check:g_boot_mode is set 99                               -> FASTBOOT_BOOT
notify_enter_fastboot:122: Notify enter fastboot.
starting app fastboot

# fastboot reboot recovery
fastboot: reboot-recovery
HALT: action = 1, reason = 7                                        -> next boot is recovery
```

Volume Up does not help either: the preloader reports it
(`Vol Up detected. Log Keep on.`) but those boots still end with
`boot_mode_check:g_boot_mode is set 0`. The keypad data is parsed
(`get_kpd_dts_info:141: kpd_hw_recovery_key = 17, kpd_hw_factory_key = 0`)
but no key path in `boot_mode_check()` uses it.

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
3. applies `tools/patches/*.patch` to `bootable/recovery` (skip-if-applied)
4. extracts `prebuilt/kernel`, `prebuilt/dtb` and `prebuilt/ramdisk` from a
   stock image or the connected device
5. runs `lunch twrp_PLC110-bp2a-userdebug` and `mka vendorbootimage`

Output:

```
out/target/product/PLC110/vendor_boot.img
```

Manual build:

```bash
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch twrp_PLC110-bp2a-userdebug
mka vendorbootimage
```

After touching anything under `bootable/recovery` (including applying a patch
by hand), drop the staged recovery root, otherwise the rebuilt binaries are not
picked up by the ramdisk:

```bash
rm -rf out/target/product/PLC110/recovery
mka vendorbootimage
```

## Prebuilts

The stock kernel, DTB and the vendor ramdisk payload are not committed
(they are listed in `.gitignore`).

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
build uses `prebuilt/dtb` and `prebuilt/ramdisk`.

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

There is no hardware key combination that boots recovery on this bootloader:
Volume Down at power-on only lands in fastboot (see [Entering recovery from
the bootloader](#entering-recovery-from-the-bootloader)). Without adb, power
off, hold Volume Down while powering on, then run `fastboot reboot recovery`.

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
* Mounting `nvdata`, `nvcfg`, `protect_f` and `protect_s`
* Flashing images and zips, backup/restore of the boot images
* `adb sideload` of zips and of `payload.bin` A/B OTA packages
* Vibration (haptics) through the `aw8697` sysfs LED

### MTK display: page-flip events must stay disabled

`mediatek-drm.ko` calls `trackpoint_report("DisplayDriverID@@503$$ invalid
vblank")` from `mtk_drm_crtc_atomic_begin()` whenever an atomic commit carries
a page-flip event (`state->base.event`) and `drm_crtc_vblank_get()` fails. That
report reaches the OPLUS AEE handler, which queues a 12 s exception work and
then resets the device: the UI appears, the kernel spams

```
[DISP]mtk_crtc_update_ddp_state frame:0 correct invalid hrt to:400, mode:0->0
trackpoint_report: event_id=12002, message:DisplayDriverID@@503$$ invalid vblank:0
trackpoint_report: queue exception work with 12000ms delay (waiting for AEE DB)
```

and the phone reboots a few seconds later. Blocking commits never set
`state->base.event`, so TWRP works around the check:

* `tools/patches/0001-twrpminui-allow-disabling-page-flip-events.patch` adds the
  `twrp.drm.page_flip_events` property to `bootable/recovery/twrpminui`
  (default `true`, so other devices keep flip events). `build.sh` and the CI
  workflow apply it automatically.
* `recovery/root/init.recovery.mt6991.rc` sets `twrp.drm.page_flip_events 0`
  in `on early-init`.

### USB: the device tree owns the gadget

TWRP's `etc/init.rc` ships its own configfs USB rules for `adb`, `sideload` and
`fastboot`, gated on `sys.usb.configfs`. They overlap with
[`recovery/root/init.recovery.usb.rc`](./recovery/root/init.recovery.usb.rc),
which builds the same gadget with the OPlus VID/PID and adds `mass_storage`
and MTP. Both sets of triggers ran; because init executes actions in
registration order the built-in `adb` rule bound the UDC first, so the device
rule then failed (`symlink .../b.1/f1: File exists`,
`write .../UDC: Device or resource busy`) and `idProduct` was written twice.

`tools/patches/0004-twrp-init-device-tree-owns-usb.patch` removes the gadget,
UDC and functionfs rules plus the `adb`/`fastboot` service starts from
`etc/init.rc`; the `adbd`/`fastbootd` service definitions, `mount pstore` and
`setprop sys.usb.config adb` stay. `init.recovery.usb.rc` is now the only place
that configures USB: it starts `adbd` for `adb`, `mtp,adb`, `sideload` and
`mass_storage,adb`, and `fastbootd` for `fastboot`.

### MTP: `sys.usb.ffs.aio_compat` must stay unset

Turning MTP on used to kill the whole USB gadget - adb and MTP both vanished
until MTP was turned off again.

`TWPartitionManager::EnableMtp()` starts with `sys.usb.config=none`, which
unbinds the gadget and stops adbd, and the `mtp,adb` bind in
`init.recovery.usb.rc` only runs once `sys.usb.ffs.mtp.ready` is 1. That
property is set by `android::writeDescriptors()` in `mtp/MtpDescriptors.cpp`,
which only `MtpFfsHandle::start()` calls. With `sys.usb.ffs.aio_compat=1`
`MtpServer` picks `MtpFfsCompatHandle` instead (`mtp/MtpServer.cpp`), whose
`start()` goes straight to `openEndpoints()`: the descriptors were never
written, so `/dev/usb-ffs/mtp/ep1..ep3` do not exist yet, the open fails and
the child retries every 800 ms forever. `ffs.mtp.ready` never flips, init never
binds the UDC, and nothing re-attaches adb.

The kernel provides AIO (`/proc/sys/fs/aio-max-nr` = 65536, `aio-nr` in use),
so the device keeps `sys.usb.ffs.aio_compat` unset and uses `MtpFfsHandle`.
When MTP is broken the recovery log stops after `I:[MTP] Starting MTP`; when it
works it continues with:

```
I:[MTP] created new TwrpMtpServer object
I:[MTP] mtppipe add storage 65545 '/data/media/0'
```

and `getprop sys.usb.ffs.mtp.ready`, `getprop sys.usb.state` report `1` and
`mtp,adb` with `ep0`..`ep3` present in `/dev/usb-ffs/mtp`.

### Reboot loop: keystore2 is a `critical` service

`/system/etc/init/keystore2.rc` in the recovery ramdisk declares

```
service keystore2 /system/bin/keystore2 /tmp/misc/keystore
    critical window=0
```

`system/core/init/service.cpp` aborts (`LOG(FATAL)` → kernel panic → reboot)
once a critical service has crashed five times while `sys.boot_completed` is
unset, which is always true in recovery. keystore2 panics on startup as soon as
it cannot reach the KeyMint HAL, so TWRP shows its UI for ~30 s and the phone
reboots:

```
init: Service 'keystore2' (pid 426) received signal 6
init: ... started service 'keystore2' has pid 491
init: Service 'keystore2' (pid 491) received signal 6
```

`init.recovery.mt6991.rc` therefore sets `init.svc_debug.no_fatal.keystore2 1`,
which is the switch init itself checks before calling `LOG(FATAL)`. keystore2
keeps restarting while the TEE is unusable, but recovery stays up.

### Trustonic TEE / KeyMint (FBE decryption)

`TW_INCLUDE_CRYPTO` is enabled and `system/vold/Decrypt.cpp` in this TWRP tree
decrypts FBE through **keystore2 → KeyMint 3.0 → mcDriverDaemon → Kinibi TEE**,
so three stock vendor services have to run inside recovery. `init.recovery.trustonic.rc`
starts them, and every one of them needs two workarounds.

1. **They must run in the `recovery` domain.** init labels
   `/vendor/bin/mcDriverDaemon` with the vendor-only `mobicore_exec` type, which
   the recovery policy does not define, so the service dies with

   ```
   init: Command 'start mobicore' ... failed: Could not start service: Could not get process context
   ```

   The KeyMint/Gatekeeper binaries do get a `hal_*` domain, but those domains
   cannot map the **ramdisk** linker and abort immediately:

   ```
   avc: denied { map } for path="/system/bin/linker64" dev="rootfs"
        scontext=u:r:hal_gatekeeper_default:s0 tcontext=u:object_r:rootfs:s0 permissive=0
   init: Service 'vendor.gatekeeper-default' (pid 2254) received signal 11
   ```

   Both are solved with `seclabel u:r:recovery:s0` (the same trick
   `keystore2.rc` uses). The `recovery` domain is permissive in TWRP, which is
   what lets the vendor binaries touch rootfs and `/dev/mobicore*`.
   Verified on hardware: with the daemon up the TEE loads the TA and reports
   `tlTeeKeymint_rpmb: Keymint TA version 3.0`.

2. **`/dev/mobicore{,-user}` are created root-only.** The stock rules live in
   `/vendor/etc/ueventd.rc` (`/dev/mobicore 0600 system system`,
   `/dev/mobicore-user 0660 system system`), which `ueventd` only applies to
   devices that appear *after* it parsed that file — the TEE nodes are created
   long before. `init.recovery.trustonic.rc` therefore chowns/chmods the two
   nodes with init builtins right before `start mobicore`.

3. **Do not put `exec_start` in that action.** With

   ```
   on property:fstab.additional=1
       exec_start tee_node_perms
       start mobicore
   ```

   init executed the exec service and then silently dropped the `start mobicore`
   command (the action never advanced past the first command), so the daemon
   never ran at boot even though `ctl.start mobicore` worked by hand. The
   builtins above are synchronous and keep the ordering without the bug.

4. **`/vendor` must stay mounted.** TWRP tears `/vendor` down several times
   while it parses the fstab (`UnmountMainPartitions()`,
   `ProcessKeymasterVersion()` and the tail of `ProcessFstab()`), and that is
   what killed the TEE stack: `mcDriverDaemon`, its `libMcClient.so` and both
   HALs all live on `/vendor`, so every start in that window failed with

   ```
   /system/etc/mcdaemon.sh[28]: /vendor/bin/mcDriverDaemon: inaccessible or not found
   == daemon exited rc=127
   ```

   `tools/patches/0002-twrp-keep-vendor-mounted.patch` makes all of those exits
   honour `ro.twrp.keep_vendor_mounted`, which `init.recovery.mt6991.rc` sets in
   `on early-init`.

### TEE session exhaustion (`NO_FREE_INSTANCES`)

Kinibi's secure world has a fixed session table (128 entries). Every
`mcOpenSession` that reaches the SWd consumes a slot, and the SWd's own error
codes explain both symptoms:

| kernel log | errno | MCP result | meaning |
|---|---|---|---|
| `open session: res 33` | `-EAGAIN` | `MC_MCP_RET_ERR_SYSTEM_NOT_READY` | TA filesystem not ready yet |
| `open session: res 4` | `-EBUSY` | `MC_MCP_RET_ERR_NO_MORE_SESSIONS` | no session slots left |

The client library maps `res 4` to `MC_DRV_ERR_NO_FREE_INSTANCES` (0x27), which
is exactly what the KeyMint HAL reports before aborting:

```
E TeeSysClient: mcOpenTrustlet returned NO_FREE_INSTANCES (rc 0x27)
F android.hardware.security.keymint@3.0-service.trustonic: Check failed: status == STATUS_OK
```

The TA is started on *every* attempt (`tlTeeKeymint_rpmb: Keymint TA version
3.0` appears each time) but the aborted open returns no session id to close
(`mcCloseSession returned UNKNOWN_SESSION (rc 0x8)`), so the slots leak until
the next reboot. While `/vendor` was missing, something retried `open session`
every 0.5 s for ~45 s, and by the time the daemon finally started the table was
exhausted — the HAL then failed forever. The cure is ordering, not code: the
daemon has to come up before that retry storm can burn through the table, which
is what the `/vendor` wait in `mcdaemon.sh` now guarantees. After a flash you
must reboot once so the SWd starts with a clean table.

`system/etc/mcdaemon.sh` wraps the daemon: it waits for `/vendor/bin/mcDriverDaemon`
to appear, retries the daemon every 5 s so a transient failure heals without init
restarting the service, and appends the spawn context plus the daemon's output to
`/tmp/mcd.log` (that log is how the `/vendor` race above was found).

KeyMint is started from `on property:ro.vendor.trustonic.ready=true` — the
property `mcDriverDaemon` sets once the TEE answers. Starting it together with
the daemon makes `HAL_CONFIGURE` fail with
`mcOpenTrustlet returned NO_FREE_INSTANCES` (rc 0x27) and then
`F Check failed: status == STATUS_OK` / SIGABRT. Every failed attempt leaks a
TA instance, so after a few crashes the TA is never openable again until the
next boot — that is why the ordering matters.

Note that the upstream `device/mediatek/sepolicy_vndr` vendor policy does not
help here: it provides the `mobicore` domain and `mobicore_exec` label, but the
`hal_*` domains would still be unable to map the rootfs linker in recovery.

`mcDriverDaemon` logs to logcat under the `TeeMcDaemon` tag, which is the
fastest way to see where the chain stops:

```
adb shell logcat -d -s TeeMcDaemon TlcKM TeeSysClient
```

### AIDL HAL registration: recovery needs its own VINTF manifest

Recovery's `servicemanager` is built with `__ANDROID_RECOVERY__`, so
`GetManifestsWithDescription()` uses `vintf::VintfObjectRecovery`, which reads
**only** `/system/etc/vintf/manifest.xml` and the fragments in
`/system/etc/vintf/manifest/` — never the device manifest on `/vendor`:

```cpp
// frameworks/native/cmds/servicemanager/ServiceManager.cpp
#ifdef __ANDROID_RECOVERY__
    return {ManifestWithDescription{vintfObject->getRecoveryHalManifest(), "recovery"}};
#endif
```

`addService()` then rejects any AIDL HAL whose instance is not declared there:

```cpp
if (!meetsDeclarationRequirements(ctx, binder, name)) {
    return Status::fromExceptionCode(Status::EX_ILLEGAL_ARGUMENT, "VINTF declaration error.");
}
```

and the Trustonic HAL treats that as fatal, so it never even gets to use the
TEE:

```
I ...: adding keymint service instance: android.hardware.security.keymint.IKeyMintDevice/default
F ...: Check failed: status == STATUS_OK      -> SIGABRT
servicemanager: Caller(...) Could not find android.hardware.security.keymint.IKeyMintDevice/default
                in the VINTF manifest. No alternative instances declared in VINTF.
```

`recovery/root/system/etc/vintf/manifest/` therefore ships copies of the vendor
declarations (`android.hardware.security.keymint-service.trustonic.xml`,
`android.hardware.security.secureclock-service.trustonic.xml`,
`android.hardware.security.sharedsecret-service.trustonic.xml`,
`android.hardware.gatekeeper-service.trustonic.xml`). They are dropped into the
ramdisk, which is where `VintfObjectRecovery` looks.

The frame buffer to watch is `adding keymint service instance:`. The Trustonic
KeyMint HAL registers **four** instances before it starts serving, and it aborts
on the first one servicemanager rejects, so *every* one of them needs a
fragment:

```
adding keymint service instance: android.hardware.security.keymint.IKeyMintDevice/default
adding keymint service instance: android.hardware.security.secureclock.ISecureClock/default
adding keymint service instance: android.hardware.security.sharedsecret.ISharedSecret/default
adding keymint service instance: android.hardware.security.keymint.IRemotelyProvisionedComponent/default
```

Missing the secureclock one looked like a TEE failure in `dmesg` because the
abort happened right after `TEE_Configure` had already opened (and leaked) the
KeyMint TA instance:

```
19:56:16.619 adding keymint service instance: ...IKeyMintDevice/default     <- ok
19:56:16.620 adding keymint service instance: ...ISecureClock/default       <- rejected
19:56:16.620 F ...: Check failed: status == STATUS_OK                       <- SIGABRT
```

### `adb sideload` of an A/B OTA: update_engine needs the boot control HAL

Sideloading a `payload.bin` package (the OPLUS full OTA the stock recovery
accepts) stopped right after the USB handshake:

```
$ adb sideload 9f6d0489097f4b3eba4f3504557df743.zip
serving: '9f6d0489097f4b3eba4f3504557df743.zip'  (~0%)
Total xfer: 0.00x
```

Nothing is transferred because the device side never asks for a single block.
`really_install_package()` detects `payload_properties.txt` (TWRP prints
`I:AB zip`), runs `/system/bin/update_engine_sideload`, and that aborts while
resolving the slots:

```
I: update_engine_sideload: [INFO:sideload_main.cc(195)] Update Engine Sideloading starting
I: update_engine_sideload: [INFO:BootControlClient.cpp(419)] AIDL IBootControl not available, falling back to HIDL.
W HidlServiceManagement: [WARN:ServiceManagement.cpp(365)] hwservicemanager is not supported on the device.
I: HidlServiceManagement: [INFO:ServiceManagement.cpp(227)] Trying to get transport of
   android.hardware.boot@1.0::IBootControl/default without hwservicemanager
E: update_engine_sideload: [ERROR:BootControlClient.cpp(426)] Error getting bootctrl v1.0 module.
E: update_engine_sideload: [ERROR:boot_control_android.cc(60)] Error getting bootctrl module.
E: update_engine_sideload: [ERROR:sideload_main.cc(147)] Error initializing the BootControlInterface.
Updater 过程结束，错误: 1
```

Recovery ships no AIDL `android.hardware.boot.IBootControl` service (TWRP's
`bootctl` mock is only wired into fastbootd) and the HIDL fallback can never
work, because `hwservicemanager` is not running in recovery. AOSP's own
`android.hardware.boot-service.default_recovery` does not help either: it
delegates to a legacy `bootctrl.<name>` module in `/vendor/lib64/hw`, which this
device does not have — MTK implements boot control as the binder service
`/vendor/bin/hw/android.hardware.boot-service.mtk`, declared in
`/vendor/etc/vintf/manifest/android.hardware.boot-service.mtk.xml`.

That service can run in TWRP, but servicemanager rejects the registration for
the same VINTF reason as the Trustonic HALs above:

```
I servicemanager: Caller(pid=1978,uid=0,sid=u:r:su:s0) Could not find
  android.hardware.boot.IBootControl/default in the VINTF manifest.
F android.hardware.boot-service.mtk: Check failed: status == STATUS_OK (status=-3)
  Failed to add service android.hardware.boot.IBootControl/default -3
```

The fix is the same pattern:

* [`recovery/root/system/etc/vintf/manifest/android.hardware.boot-service.mtk.xml`](./recovery/root/system/etc/vintf/manifest/android.hardware.boot-service.mtk.xml)
  declares `IBootControl/default` in the recovery manifest;
* [`recovery/root/init.recovery.bootctl.rc`](./recovery/root/init.recovery.bootctl.rc)
  starts the vendor HAL once TWRP has mounted `/vendor` (`fstab.additional=1`),
  in the permissive `recovery` domain like the other vendor daemons.

With both in place the same probe now reports

```
I: update_engine_sideload: [INFO:BootControlClient.cpp(416)] Using AIDL version of IBootControl
I: update_engine_sideload: [INFO:boot_control_android.cc(64)] Loaded boot control hal.
I servicemanager: Caller(...) Found android.hardware.boot.IBootControl/default in recovery VINTF manifest.
```

and `update_engine_sideload` moves on to read the payload through the FUSE
mount of `/sideload/package.zip`. As a side effect `fastbootd` can now use the
real `IBootControl` instead of only the TWRP mock when switching slots.

**Ordering trap:** declaring the instance also changes TWRP's own startup, because
`TWPartitionManager::GetSuperPartition()` asks the HAL for the current slot at the
very start of `ProcessFstab()`:

```cpp
// hardware/interfaces/boot/aidl/client/BootControlClient.cpp
if (AServiceManager_isDeclared(instance_name.c_str())) {
    auto module = IBootControl::fromBinder(
            ndk::SpAIBinder(AServiceManager_waitForService(instance_name.c_str())));
```

`AServiceManager_waitForService()` never returns while a *declared* instance is
missing, and the HAL cannot start before `/vendor` is mounted — which TWRP only
does later in that same function (`fstab.additional=1` is set after it copied
`/vendor/etc/fstab.mt6991`). The result is a deadlock that looks like a hang on
the TWRP splash:

```
gui2: 1272x2800, short side 71 mm, scale 1.06
=> Linking mtab
=> Processing /etc/recovery.fstab      <- last line, nothing after it
```

with `adb` still working, `/dev/block/mapper` empty and `fstab.additional` unset
(so `init.svc.vendor.boot-default` never starts either).

`tools/patches/0006-twrp-do-not-block-on-boot-control.patch` therefore lets the
device tree pin the name with `ro.twrp.super_partition` (set to `super` in
`init.recovery.mt6991.rc`); on this platform super is a plain, non-suffixed
partition, so the HAL is not needed to name it. The other `WaitForService()`
call sites (`SetActiveSlot`, `Flash_Current_Twrp`, `update_verifier`) run from
user actions long after `/vendor` is up, so they still use the real HAL.

### Reboot always returning to recovery: the `/misc` boot command

MTK's LK reads the Android bootloader control block (BCB) from `/misc` on every
boot, and a pending `boot-recovery` command takes precedence over both the
reboot reason and the hardware key combos. TWRP used to leave that command
behind, so *every* reboot (and every key combination) landed in recovery again:

```
$ dd if=/dev/block/by-name/misc bs=32 count=1 | tr -d '\0'
boot-recovery
```

`tools/patches/0003-twrp-misc-boot-command.patch` makes `TWFunc::TwReboot()`
rewrite the 32-byte `command` field first:

| reboot target | BCB `command` written |
|---|---|
| System | cleared |
| Recovery | `boot-recovery` |
| Bootloader / Fastbootd | cleared (the `reboot,bootloader` reason is used) |
| Power off / Download / EDL | cleared |

Recovery also clears it once startup has finished
(`twrp_startup_backend::run()`), so a long power-button press ends up in the
system instead of coming straight back.

Only offset 0..31 is touched. **Do not zero a larger block**: `struct
bootloader_message` is exactly 2048 bytes and the A/B slot metadata
(`bootloader_control`: `slot_suffix`, magic `BCAB`, per-slot
successful/tries/priority and its CRC) starts at offset 2048. Clearing 4 KiB
wipes it, the bootloader falls back to slot `a`, and the device bootloops
until `fastboot --set-active=<slot>` or the field is restored:

```
0x0000  boot-recovery            <- BCB command
0x0800  _ b \0 \0 B C A B 001 002 ...   <- slot_suffix + bootloader_control
```

### `adb reboot recovery` stalls: `/misc` must be in `recovery.fstab`

`adb reboot recovery` never rebooted and adb waited forever, while a plain
`adb reboot` worked and booted the system.

`HandlePowerctlMessage()` writes `boot-recovery` into the BCB *before* the
shutdown starts, and returns without rebooting when it cannot:

```
init: Received sys.powerctl='reboot,recovery' from pid: 6631 (/system/bin/reboot)
init: Got shutdown_command 'reboot,recovery' Calling HandlePowerctlMessage()
init: Failed to read bootloader message: failed to find /misc partition
init: Failed to set bootloader message: failed to find /misc partition
```

No `Reboot start` follows. A plain `reboot` uses the `shell` target, never
touches the BCB, and therefore worked.

`get_misc_blk_device()` (`libbootloader_message`) searches
`ReadDefaultFstab()` for an entry whose mount point is `/misc`. In recovery the
TWRP `fs_mgr` resolves that to **`/etc/recovery.fstab`**, the file this device
tree ships; the stock `/first_stage_ramdisk/fstab.mt6991` and
`/vendor/etc/fstab.mt6991` both list `/misc`, but init does not read them here.
The entry is therefore part of `recovery.fstab`:

```
/dev/block/by-name/misc /misc emmc defaults defaults
```

Checked on the device: appending that line at runtime makes
`adb shell reboot recovery` come back to recovery in ~35 s, without it init logs
the two errors and stays put. `adb reboot sideload` and `adb reboot fastboot`
take the same path. TWRP never mounts `/misc`, and the vendor fstab pass only
refines `/data` and `/metadata`, so the extra partition is inert for TWRP.

Needs testing / extra work:

* **FBE decryption**: the chain above works, but the full user-credential flow
  (gatekeeper unlock → keystore2 unwrap → vold decrypt of `/data`) is untested
  on hardware. Because TWRP unmounts `/vendor` after startup, a KeyMint crash
  later in the session cannot be recovered (init cannot exec the binary), so the
  daemons are expected to stay resident.
* **FBE decryption on the V17 firmware**: after the system update to Android 17
  the Trustonic store no longer mounts in recovery, so the KeyMint HAL never
  comes up and `/data` stays encrypted. `mcDriverDaemon` gets as far as
  `TAFileServer` `Mounting partition 1...`, after which the secure world sends no
  further notification (`wait_mcp_notification: no answer after 10s …`) while the
  daemon's main thread is blocked in `mcOpenSession` for the first `-r` secure
  driver under `Load secure drivers`. The same kernel, kernel modules, TEE
  firmware and store work when Android boots, so the difference is in the
  recovery environment; `rpmb-mtk.ko` contention and file-system problems have
  been ruled out. See the debug switches below.
* Fastbootd (the TWRP mock boot control HAL is used; slot switching depends
  on the vendor `IBootControl` service).
* WiFi is not enabled (no firmware setup is included).

`recovery/root/system/etc/mcdaemon.sh` reads three optional files from
`/mnt/vendor/persist` so the TEE daemon can be varied without rebuilding the
image: `.mcd_skip` (one substring per line, drops matching `-r` entries),
`.mcd_args` (complete argument list override) and `.mcd_wait` (the daemon is not
started until the file is deleted). They are absent in normal use.

The recovery ramdisk ships its own `lib/modules/modules.load.recovery` without
`rpmb-mtk.ko` and `mtk-mmc.ko`: the former's kthread opens a Trustonic session
every 512 ms from 1.2 s on, while `mcDriverDaemon` cannot start before `/vendor`
is mounted at ~14 s, and `mtk-mmc.ko` is the only module that depends on it
(it never binds on this UFS-only device, and init's `Modprobe` would pull
`rpmb-mtk.ko` back in through `modules.dep`). `build/tasks/recovery_ramdisk_files.mk`
fails the build when a new stock image changes that list.

### Haptics: `aw8697` needs its RAM firmware from the ramdisk

`DataManager::Vibrate()` writes `duration` and then `activate` to
`/sys/class/leds/vibrator`, and the driver answered every write with

```
[haptic_hv]activate_store: value=1
[haptic_hv]activate_store: ram init failed, not allow to play!
```

`haptic.ko` loads its waveform in `ram_update` during probe and again through an
hrtimer that retries 20 times (`load_cont1` … `load_cont20`), all within the
first ~30 s of boot:

```
[haptic_hv]ram_update:170Hz haptic bin name aw8697_haptic_170.bin
haptic_hv 5-005a: Direct firmware load for aw8697_haptic_170.bin failed with error -2
[haptic_hv]ram_load: failed to read ram firmware!
```

The firmware is not in `/vendor/firmware`; it ships in **`odm`**
(`/odm/firmware/aw8697_haptic_170.bin`, `_soft` variant and `aw8697_rtp.bin`),
and TWRP never mounts `odm` at that point. The kernel searches only
`/sys/module/firmware_class/parameters/path` (a single directory, `/vendor/firmware`
here), so the odm copy is unreachable. Proof: mounting `odm` and running

```
echo -n /odm/firmware > /sys/module/firmware_class/parameters/path
echo 1 > /sys/class/leds/vibrator/ram_update
```

makes `ram_load` report `check sum pass` → `container_update` → `ram firmware
update complete`, and `activate` plays in `ram loop mode`.

The three files are therefore committed under
[`recovery/root/vendor/firmware/`](./recovery/root/vendor/firmware), which the
recovery ramdisk overlay unpacks over the initramfs `/vendor/firmware`. `init`
loads the module at ~3.1 s, before the erofs `/vendor` is mounted, so the very
first `ram_update` already finds them. (`aw8697.ko` is also in the stock module
set and always fails with `aw8697_read_chipid unsupported device revision
(0x82)`; the working driver for this panel is `haptic.ko`.)

### Mounting `/mnt/vendor/*`: TWRP truncates the path to `/mnt`

`nvdata`, `nvcfg`, `protect_f` and `protect_s` appeared **twice** in the Mount
list and neither row worked. TWRP's `TWFunc::GetRootPath()` shortens a path to
its first component so that `/data/media/0/x.zip` becomes `/data`, and every
partition lookup reused it:

```
static bool MatchesPath(...) -> mount_point_ == path
FindPartitionByPath("/mnt/vendor/nvdata")  ->  looks for "/mnt"  ->  nullptr
```

So `ProcessFstab()` created the partition from `recovery.fstab`, then
`AddRemainingTwrpFlags()` could not find it and added the same mount point a
second time from `twrp.flags`, while `MountByPath()` (used by the Mount page
toggle in `gui2/backend/twrp_mount_backend.cpp`) resolved `/mnt` and reported
`unable_find_part_path`.

`tools/patches/0005-twrp-resolve-nested-mount-points.patch` adds
`TWPartitionManager::ResolvePartitionPath()`, which looks the exact mount point
up first and only falls back to `GetRootPath()`. All partition lookups
(`FindPartitionByPath`, `MountByPath`, `UnmountByPath`, `WipeByPath`,
`RepairByPath`, `ResizeByPath`, `RemovePartitionByPath`) use it, so nested mount
points work and no duplicate entries are created.

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
build/tasks/recovery_ramdisk_files.mk  repack prebuilt/ramdisk into the PLATFORM fragment
recovery/root/system/etc/vintf/manifest/  recovery VINTF fragments for the AIDL HALs
recovery/root/system/etc/mcdaemon.sh     TEE daemon wrapper (waits for /vendor, retries, logs)
recovery/root/init.recovery.bootctl.rc   vendor boot control HAL (needed by update_engine_sideload)
recovery/root/vendor/firmware/      aw8697 haptic RAM firmware taken from odm
prebuilt/                          kernel, dtb, ramdisk files (generated)
tools/extract-prebuilts.*          stock image extraction helpers
tools/patches/*.patch              TWRP source patches applied by build.sh / CI
```

## Notes

* Partition sizes and the dynamic-partition list were read from the device
  (`blockdev --getsize64`, `lpdump`): super `14680064000` bytes, group `main`
  `14675869696` bytes.
* The stock kernel modules are packed into the recovery ramdisk and loaded by
  first stage init through `modules.load.recovery`, so
  `TW_LOAD_VENDOR_MODULES` is intentionally not set. Add it only for modules
  that are missing from the stock set.
* `TW_Y_OFFSET` / `TW_H_OFFSET` use the real 141 px cutout height reported by
  `dumpsys window displays`.
* `TW_CUSTOM_CPU_TEMP_PATH` points at `thermal_zone5` (`soc_max`). The zones
  on this kernel are: 5 `soc_max`, 21 `cpu-big-core7-0`, 45
  `slave_cp_temp` (the old value was the wrong zone).
* `TW_MAX_BRIGHTNESS` is `4094`, not the TWRP default `255`: `leds-mtk` on this
  kernel exposes `/sys/class/leds/lcd-backlight` with `max_brightness` =
  `logic_max_brightness` = `max_hw_brightness` = `4094`. With the 255 default
  the slider saturated at 255 (≈6 % DBV), so the screen stayed dim even at
  100 %. `TW_DEFAULT_BRIGHTNESS` is set to 1638 (40 %).

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