#!/bin/bash
#
# TWRP 16 build script for OnePlus Ace 5 Ultra (PLC110, MT6991)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
#   ./build.sh --skip-sync
#   ./build.sh --skip-prebuilts
#
set -eo pipefail

# ============================================================
# Configuration
# ============================================================
DEVICE="PLC110"
DEVICE_PATH="device/oneplus/PLC110"
TWRP_MANIFEST="https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git"
TWRP_BRANCH="twrp-16.0"

WORK_DIR="${WORK_DIR:-${HOME}/twrp_build}"
TWRP_DIR="${WORK_DIR}/twrp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIP_SYNC=0
SKIP_PREBUILTS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ============================================================
# Arguments
# ============================================================
for arg in "$@"; do
    case "${arg}" in
        --skip-sync) SKIP_SYNC=1 ;;
        --skip-prebuilts) SKIP_PREBUILTS=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            log_error "Unknown argument: ${arg}"
            exit 1
            ;;
    esac
done

# ============================================================
# Prerequisites
# ============================================================
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=()
    for cmd in git python3 curl repo java; do
        command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing commands: ${missing[*]}"
        cat <<'EOF'
Install the Android 16 build dependencies, for example on Ubuntu 24.04:

  sudo apt update
  sudo apt install -y git curl python3 repo openjdk-21-jdk \
      build-essential bc bison flex libssl-dev libncurses-dev \
      libxml2-utils xsltproc lib32z1 lib32ncurses-dev lib32stdc++6 \
      libc6-dev-i386 ccache lz4 zstd imagemagick pngcrush schedtool \
      squashfs-tools dosfstools mtools erofs-utils
EOF
        exit 1
    fi

    if ! java -version 2>&1 | grep -qE '"(2[1-9]|[3-9][0-9])'; then
        log_warn "Android 16 needs OpenJDK 21 or newer. Current:"
        java -version 2>&1 | head -n 1
    fi

    local avail
    avail=$(df -Pk "${HOME}" | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "${avail}" -lt 200 ]; then
        log_warn "Only ${avail} GiB free under ${HOME}; a full TWRP 16 tree needs ~250 GiB."
    fi

    log_info "Prerequisites OK"
}

# ============================================================
# Workspace
# ============================================================
setup_workspace() {
    log_step "Setting up TWRP 16 workspace..."
    mkdir -p "${WORK_DIR}"

    if [ ! -d "${TWRP_DIR}/.repo" ]; then
        log_info "Initializing ${TWRP_MANIFEST} (${TWRP_BRANCH})"
        mkdir -p "${TWRP_DIR}"
        cd "${TWRP_DIR}"
        repo init --depth=1 -u "${TWRP_MANIFEST}" -b "${TWRP_BRANCH}"
    fi

    if [ "${SKIP_SYNC}" -eq 0 ]; then
        log_info "Syncing sources (this can take a long time)"
        cd "${TWRP_DIR}"
        repo sync -c -j"$(nproc --all)" --force-sync --no-clone-bundle --no-tags
    else
        log_warn "Skipping repo sync"
    fi

    log_info "Copying device tree to ${DEVICE_PATH}"
    rm -rf "${TWRP_DIR:?}/${DEVICE_PATH}"
    mkdir -p "${TWRP_DIR}/${DEVICE_PATH}"
    cp -a "${SCRIPT_DIR}/." "${TWRP_DIR}/${DEVICE_PATH}/"
    rm -rf "${TWRP_DIR}/${DEVICE_PATH}/.git" \
           "${TWRP_DIR}/${DEVICE_PATH}/out" \
           "${TWRP_DIR}/${DEVICE_PATH}/stock"

    log_info "Workspace ready: ${TWRP_DIR}"
}

# ============================================================
# TWRP source patches
# ============================================================
# The device needs a small twrpminui change, so keep it as a patch instead of
# asking every builder to edit bootable/recovery by hand.
apply_recovery_patches() {
    local patches_dir="${TWRP_DIR}/${DEVICE_PATH}/tools/patches"
    local projects=("${TWRP_DIR}/bootable/recovery" "${TWRP_DIR}/hardware/interfaces" \
                    "${TWRP_DIR}/system/core")

    [ -d "${patches_dir}" ] || return 0

    log_step "Applying TWRP source patches..."
    local patch project applied
    for patch in "${patches_dir}"/*.patch; do
        [ -e "${patch}" ] || continue
        applied=0
        for project in "${projects[@]}"; do
            [ -d "${project}" ] || continue
            if git -C "${project}" apply --reverse --check "${patch}" >/dev/null 2>&1; then
                log_info "$(basename "${patch}") already applied"
                applied=1
                break
            fi
            if git -C "${project}" apply --check "${patch}" >/dev/null 2>&1; then
                git -C "${project}" apply "${patch}"
                log_info "Applied $(basename "${patch}")"
                applied=1
                break
            fi
        done
        if [ "${applied}" -eq 0 ]; then
            log_error "Could not apply $(basename "${patch}") to bootable/recovery, hardware/interfaces or system/core"
            exit 1
        fi
    done
}

# ============================================================
# Prebuilts
# ============================================================
prepare_prebuilts() {
    local device_dir="${TWRP_DIR}/${DEVICE_PATH}"
    local need=0
    for f in kernel dtb ramdisk/lib/modules/modules.load ramdisk/lib/modules/modules.dep \
             ramdisk/first_stage_ramdisk/fstab.mt6991; do
        if [ ! -s "${device_dir}/prebuilt/${f}" ]; then
            log_warn "Missing prebuilt/${f}"
            need=1
        fi
    done

    if [ "${need}" -eq 0 ]; then
        log_info "Prebuilts present"
        return 0
    fi

    if [ "${SKIP_PREBUILTS}" -eq 1 ]; then
        log_error "Prebuilts are missing and --skip-prebuilts was given"
        exit 1
    fi

    log_step "Extracting stock kernel / dtb / vendor ramdisk payload"
    ( cd "${device_dir}" && bash tools/extract-prebuilts.sh )
}

# ============================================================
# Build
# ============================================================
build_twrp() {
    log_step "Building TWRP vendor_boot image..."

    cd "${TWRP_DIR}"
    # shellcheck disable=SC1091
    source build/envsetup.sh
    export ALLOW_MISSING_DEPENDENCIES=true
    export LC_ALL=C

    lunch "twrp_${DEVICE}-bp2a-userdebug"
    mka vendorbootimage

    local output_img="${TWRP_DIR}/out/target/product/${DEVICE}/vendor_boot.img"
    if [ ! -f "${output_img}" ]; then
        log_error "Build finished without ${output_img}"
        exit 1
    fi

    cp -f "${output_img}" "${WORK_DIR}/twrp_${DEVICE}_vendor_boot.img"
    log_info "========================================="
    log_info "BUILD SUCCESSFUL"
    log_info "Image: ${WORK_DIR}/twrp_${DEVICE}_vendor_boot.img"
    log_info "========================================="
    ls -lh "${WORK_DIR}/twrp_${DEVICE}_vendor_boot.img"

    verify_image "${output_img}"
}

# ============================================================
# Verify vendor_boot fragments
# ============================================================
verify_image() {
    local image="$1"
    local unpack="${TWRP_DIR}/${DEVICE_PATH}/tools/unpack_bootimg.py"
    [ -f "${unpack}" ] || return 0

    log_step "Vendor boot ramdisk table"
    python3 "${unpack}" --boot_img "${image}" --format info | \
        grep -E 'vendor ramdisk table|vendor_ramdisk|type:|size:|offset:|vendor boot image header|dtb size|vendor command line' || true
}

# ============================================================
# Flash instructions
# ============================================================
print_flash_instructions() {
    local image="${WORK_DIR}/twrp_${DEVICE}_vendor_boot.img"
    cat <<EOF

=========================================
  FLASHING INSTRUCTIONS
=========================================

The bootloader must be unlocked. TWRP is not a recovery partition image on
this device: it is a RECOVERY ramdisk fragment inside vendor_boot.img.

0. Back up the stock vendor_boot of both slots (root required):
   adb shell su -c "dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot_a.img"
   adb shell su -c "dd if=/dev/block/by-name/vendor_boot_b of=/sdcard/vendor_boot_b.img"
   adb pull /sdcard/vendor_boot_a.img
   adb pull /sdcard/vendor_boot_b.img

1. Reboot to the bootloader:
   adb reboot bootloader

2. Flash the image (both slots is safest):
   fastboot flash vendor_boot_a ${image}
   fastboot flash vendor_boot_b ${image}

3. Boot recovery:
   fastboot reboot recovery

   If the bootloader does not support that, power off and hold
   Volume Down + Power to enter recovery.

4. Restore the stock vendor_boot if needed:
   fastboot flash vendor_boot_a vendor_boot_a.img
   fastboot flash vendor_boot_b vendor_boot_b.img

=========================================
EOF
}

# ============================================================
# Main
# ============================================================
main() {
    echo ""
    echo "========================================="
    echo "  TWRP 16 build for OnePlus Ace 5 Ultra"
    echo "  Device: ${DEVICE}  (MT6991)"
    echo "  Manifest: ${TWRP_BRANCH}"
    echo "========================================="
    echo ""

    check_prerequisites
    setup_workspace
    apply_recovery_patches
    prepare_prebuilts
    build_twrp
    print_flash_instructions
}

main