#!/bin/bash
#
# Extract the prebuilts needed to build the PLC110 TWRP vendor_boot image:
# prebuilt/kernel, prebuilt/dtb and prebuilt/ramdisk (the stock kernel modules
# and touch firmware taken from the factory PLATFORM ramdisk).
#
# Sources, in order of preference:
#   1. --boot/--vendor-boot <file> (stock images)
#   2. $STOCK_DIR/boot.img and $STOCK_DIR/vendor_boot.img
#   3. a rooted device connected over adb
#   4. the stock image mirror (STOCK_URL)
#
# Usage:
#   ./tools/extract-prebuilts.sh
#   ./tools/extract-prebuilts.sh --boot boot.img --vendor-boot vendor_boot.img
#   ./tools/extract-prebuilts.sh --download
#   ./tools/extract-prebuilts.sh --from-device
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt"
STOCK_DIR="${STOCK_DIR:-${REPO_ROOT}/stock}"
STOCK_URL="${STOCK_URL:-https://file.hty1234.eu.org}"
UNPACK_PY="${REPO_ROOT}/tools/unpack_bootimg.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

BOOT_IMG=""
VENDOR_BOOT_IMG=""
MODE="auto"

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --boot) BOOT_IMG="$2"; MODE="files"; shift 2 ;;
        --vendor-boot) VENDOR_BOOT_IMG="$2"; MODE="files"; shift 2 ;;
        --from-device) MODE="device"; shift ;;
        --download) MODE="download"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

mkdir -p "${PREBUILT_DIR}"

download_unpack() {
    if [ -x "${UNPACK_PY}" ] || [ -f "${UNPACK_PY}" ]; then
        return 0
    fi
    echo "[INFO] Downloading unpack_bootimg.py"
    local b64="${TMP_DIR}/unpack.b64"
    curl -fsSL "https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/unpack_bootimg.py?format=TEXT" -o "${b64}"
    python3 - "${b64}" "${UNPACK_PY}" <<'PY'
import base64, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as f:
    data = base64.b64decode(f.read())
with open(dst, 'wb') as f:
    f.write(data)
PY
}

pull_from_device() {
    local slot
    slot="$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
    [ -n "${slot}" ] || slot="_b"
    echo "[INFO] Pulling boot${slot} and vendor_boot${slot} from device"
    adb shell "su -c 'dd if=/dev/block/by-name/boot${slot} of=/data/local/tmp/plc110_boot.img bs=1M'" >/dev/null
    adb shell "su -c 'dd if=/dev/block/by-name/vendor_boot${slot} of=/data/local/tmp/plc110_vendor_boot.img bs=1M'" >/dev/null
    adb pull /data/local/tmp/plc110_boot.img "${TMP_DIR}/boot.img" >/dev/null
    adb pull /data/local/tmp/plc110_vendor_boot.img "${TMP_DIR}/vendor_boot.img" >/dev/null
    adb shell "su -c 'rm -f /data/local/tmp/plc110_boot.img /data/local/tmp/plc110_vendor_boot.img'" >/dev/null || true
    BOOT_IMG="${TMP_DIR}/boot.img"
    VENDOR_BOOT_IMG="${TMP_DIR}/vendor_boot.img"
}

download_images() {
    echo "[INFO] Downloading stock images from ${STOCK_URL}"
    curl -fL "${STOCK_URL}/boot.img" -o "${TMP_DIR}/boot.img"
    curl -fL "${STOCK_URL}/vendor_boot.img" -o "${TMP_DIR}/vendor_boot.img"
    BOOT_IMG="${TMP_DIR}/boot.img"
    VENDOR_BOOT_IMG="${TMP_DIR}/vendor_boot.img"
}

if [ "${MODE}" = "auto" ]; then
    if [ -f "${STOCK_DIR}/boot.img" ] && [ -f "${STOCK_DIR}/vendor_boot.img" ]; then
        BOOT_IMG="${STOCK_DIR}/boot.img"
        VENDOR_BOOT_IMG="${STOCK_DIR}/vendor_boot.img"
    elif command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
        pull_from_device
    else
        download_images
    fi
elif [ "${MODE}" = "device" ]; then
    pull_from_device
elif [ "${MODE}" = "download" ]; then
    download_images
fi

if [ -z "${BOOT_IMG}" ] || [ -z "${VENDOR_BOOT_IMG}" ]; then
    echo "[ERROR] Both boot and vendor_boot images are required" >&2
    exit 1
fi
for f in "${BOOT_IMG}" "${VENDOR_BOOT_IMG}"; do
    [ -f "$f" ] || { echo "[ERROR] Missing $f" >&2; exit 1; }
done

download_unpack
python3 "${UNPACK_PY}" --boot_img "${BOOT_IMG}" --out "${TMP_DIR}/boot" --format mkbootimg >/dev/null
python3 "${UNPACK_PY}" --boot_img "${VENDOR_BOOT_IMG}" --out "${TMP_DIR}/vendor_boot" --format mkbootimg >/dev/null

cp -f "${TMP_DIR}/boot/kernel" "${PREBUILT_DIR}/kernel"
cp -f "${TMP_DIR}/vendor_boot/dtb" "${PREBUILT_DIR}/dtb"

# The kernel modules, the touch firmware and the first stage fstab live in the
# factory PLATFORM ramdisk; they are repacked into our own PLATFORM fragment
# instead of shipping the 40 MB factory one (see README).
rm -rf "${PREBUILT_DIR}/ramdisk"
python3 "${REPO_ROOT}/tools/extract_ramdisk_files.py" \
    --ramdisk "${TMP_DIR}/vendor_boot/vendor_ramdisk00" \
    --dest "${PREBUILT_DIR}/ramdisk"

echo "[INFO] Prebuilts written to ${PREBUILT_DIR}"
ls -l "${PREBUILT_DIR}/kernel" "${PREBUILT_DIR}/dtb"
du -sh "${PREBUILT_DIR}/ramdisk/lib/modules" "${PREBUILT_DIR}/ramdisk/vendor/firmware"
ls -l "${PREBUILT_DIR}/ramdisk/first_stage_ramdisk/fstab.mt6991"
