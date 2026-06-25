#!/bin/bash
#
# TWRP Build Script for OnePlus Ace 5 Racing Edition (PLF110)
# Platform: MediaTek Dimensity 9400e (MT6991)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
#

set -e

# ============================================================
# Configuration
# ============================================================
DEVICE="PLF110"
DEVICE_TREE="device_oneplus_PLF110-TWRP"
TWRP_BRANCH="android-12.1"
MT6991_KERNEL_BRANCH="oneplus/mt6991_b_16.0.0_oneplus_ace5_ultra"
KERNEL_DEFCONFIG="gki_defconfig"

WORK_DIR="${HOME}/twrp_build"
TWRP_DIR="${WORK_DIR}/twrp"
DEVICE_DIR="${TWRP_DIR}/${DEVICE_TREE}"

# Colors
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
# Check prerequisites
# ============================================================
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check Ubuntu version
    if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
        log_warn "This script is designed for Ubuntu. Proceed with caution."
    fi

    # Check required packages
    local packages=(
        git curl wget zip unzip
        build-essential clang lld llvm
        python3 python3-pip
        openjdk-17-jdk
        lib32z1 lib32ncurses-dev lib32stdc++6
        bc bison flex
        libssl-dev
        libc6-dev-i386
        xsltproc
        repo
    )

    local missing=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing packages: ${missing[*]}"
        log_info "Installing missing packages..."
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    fi

    # Check Java
    if ! java -version &>/dev/null; then
        log_error "Java not found. Install OpenJDK 17:"
        echo "  sudo apt-get install openjdk-17-jdk"
        exit 1
    fi

    # Check repo
    if ! command -v repo &>/dev/null; then
        log_info "Installing repo tool..."
        mkdir -p ~/bin
        curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
        chmod a+x ~/bin/repo
        export PATH="${HOME}/bin:${PATH}"
    fi

    log_info "Prerequisites OK"
}

# ============================================================
# Setup workspace
# ============================================================
setup_workspace() {
    log_step "Setting up workspace..."

    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    # Initialize TWRP repo
    if [ ! -d "${TWRP_DIR}" ]; then
        log_info "Initializing TWRP repository..."
        mkdir -p "${TWRP_DIR}"
        cd "${TWRP_DIR}"
        repo init -u https://github.com/nictas/android.git -b "${TWRP_BRANCH}" --depth=1
        repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags --depth=1
    else
        log_info "TWRP repo already exists at ${TWRP_DIR}"
    fi

    cd "${TWRP_DIR}"

    # Copy device tree
    if [ ! -d "${DEVICE_DIR}" ]; then
        log_info "Copying device tree..."
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cp -r "${script_dir}" "${DEVICE_DIR}"
    fi

    log_info "Workspace ready at ${TWRP_DIR}"
}

# ============================================================
# Build kernel (if needed)
# ============================================================
build_kernel() {
    log_step "Building kernel for MT6991..."

    local kernel_dir="${WORK_DIR}/kernel"

    if [ ! -d "${kernel_dir}" ]; then
        log_info "Cloning OnePlus MT6991 kernel source..."
        cd "${WORK_DIR}"
        git clone --depth=1 -b "${MT6991_KERNEL_BRANCH}" \
            https://github.com/OnePlusOSS/android_kernel_oneplus_mt6991.git kernel
    fi

    cd "${kernel_dir}"

    # Check if prebuilt kernel exists
    local prebuilt_dir="${DEVICE_DIR}/prebuilt"
    mkdir -p "${prebuilt_dir}"

    if [ -f "${prebuilt_dir}/kernel" ]; then
        log_info "Prebuilt kernel already exists, skipping build"
        return 0
    fi

    log_info "Configuring kernel..."
    export ARCH=arm64
    export SUBARCH=arm64
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

    make "${KERNEL_DEFCONFIG}" -j$(nproc --all)

    log_info "Building kernel..."
    make -j$(nproc --all) 2>&1 | tee "${WORK_DIR}/kernel_build.log"

    # Find and copy kernel image
    local kernel_image=""
    if [ -f "out/arch/arm64/boot/Image.gz" ]; then
        kernel_image="out/arch/arm64/boot/Image.gz"
    elif [ -f "out/arch/arm64/boot/Image" ]; then
        kernel_image="out/arch/arm64/boot/Image"
    elif [ -f "Image.gz" ]; then
        kernel_image="Image.gz"
    elif [ -f "Image" ]; then
        kernel_image="Image"
    fi

    if [ -n "${kernel_image}" ]; then
        cp "${kernel_image}" "${prebuilt_dir}/kernel"
        log_info "Kernel built successfully: ${kernel_image}"
    else
        log_error "Kernel image not found after build"
        log_error "Check ${WORK_DIR}/kernel_build.log"
        exit 1
    fi
}

# ============================================================
# Build TWRP
# ============================================================
build_twrp() {
    log_step "Building TWRP recovery..."

    cd "${TWRP_DIR}"

    # Set environment
    source build/envsetup.sh

    # Lunch
    lunch "twrp_${DEVICE}-user"

    # Build
    log_info "Starting build..."
    mka recoveryimage -j$(nproc --all) 2>&1 | tee "${WORK_DIR}/twrp_build.log"

    # Check output
    local output_img="${TWRP_DIR}/out/target/product/${DEVICE}/recovery.img"
    if [ -f "${output_img}" ]; then
        cp "${output_img}" "${WORK_DIR}/twrp_${DEVICE}_recovery.img"
        log_info "========================================="
        log_info "BUILD SUCCESSFUL!"
        log_info "Recovery image: ${WORK_DIR}/twrp_${DEVICE}_recovery.img"
        log_info "========================================="
        ls -lh "${WORK_DIR}/twrp_${DEVICE}_recovery.img"
    else
        log_error "Build failed. Check ${WORK_DIR}/twrp_build.log"
        exit 1
    fi
}

# ============================================================
# Flash instructions
# ============================================================
print_flash_instructions() {
    echo ""
    echo "========================================="
    echo "  FLASHING INSTRUCTIONS"
    echo "========================================="
    echo ""
    echo "1. Boot into fastboot mode:"
    echo "   adb reboot bootloader"
    echo ""
    echo "2. Flash recovery:"
    echo "   fastboot flash recovery ${WORK_DIR}/twrp_${DEVICE}_recovery.img"
    echo ""
    echo "3. Boot to recovery:"
    echo "   fastboot reboot recovery"
    echo ""
    echo "OR boot without flashing:"
    echo "   fastboot boot ${WORK_DIR}/twrp_${DEVICE}_recovery.img"
    echo ""
    echo "========================================="
}

# ============================================================
# Main
# ============================================================
main() {
    echo ""
    echo "========================================="
    echo "  TWRP Build for OnePlus Ace 5 Racing"
    echo "  Device: ${DEVICE}"
    echo "  Platform: MT6991 (Dimensity 9400e)"
    echo "========================================="
    echo ""

    check_prerequisites
    setup_workspace
    build_kernel
    build_twrp
    print_flash_instructions
}

# Parse arguments
case "${1:-}" in
    --skip-kernel)
        SKIP_KERNEL=1
        ;;
    --help|-h)
        echo "Usage: $0 [--skip-kernel]"
        echo ""
        echo "Options:"
        echo "  --skip-kernel  Skip kernel build (use existing prebuilt)"
        echo "  --help, -h     Show this help"
        ;;
    *)
        main
        ;;
esac
