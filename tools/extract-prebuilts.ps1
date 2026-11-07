<#
.SYNOPSIS
    Extract the prebuilts needed to build the PLC110 TWRP vendor_boot image.

.DESCRIPTION
    Produces:
      prebuilt/kernel     stock GKI kernel (from boot.img)
      prebuilt/dtb        stock DTB (from vendor_boot.img)
      prebuilt/ramdisk    lib/modules (kernel modules + libmodprobe lists) and
                          vendor/firmware (touch firmware) taken from the
                          PLATFORM ramdisk and packed into the TWRP recovery
                          ramdisk

    Sources, in order of preference:
      1. -BootImg / -VendorBootImg
      2. stock\boot.img and stock\vendor_boot.img
      3. a rooted device connected over adb
      4. the stock image mirror (-StockUrl)

.EXAMPLE
    .\tools\extract-prebuilts.ps1
    .\tools\extract-prebuilts.ps1 -BootImg boot.img -VendorBootImg vendor_boot.img
    .\tools\extract-prebuilts.ps1 -Download
    .\tools\extract-prebuilts.ps1 -FromDevice
#>
[CmdletBinding()]
param(
    [string]$BootImg,
    [string]$VendorBootImg,
    [switch]$FromDevice,
    [switch]$Download,
    [string]$StockUrl = 'https://file.hty1234.eu.org'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$prebuiltDir = Join-Path $repoRoot 'prebuilt'
$stockDir = Join-Path $repoRoot 'stock'
$unpackPy = Join-Path $PSScriptRoot 'unpack_bootimg.py'
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("plc110_prebuilts_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $prebuiltDir, $tmpDir | Out-Null

function Get-Python {
    foreach ($candidate in @('python', 'py')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw 'Python 3 is required'
}

$python = Get-Python

function Get-UnpackBootimg {
    if (Test-Path $unpackPy) { return }
    Write-Host '[INFO] Downloading unpack_bootimg.py'
    $b64 = Join-Path $tmpDir 'unpack.b64'
    & curl.exe -fsSL 'https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/unpack_bootimg.py?format=TEXT' -o $b64
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download unpack_bootimg.py' }
    $bytes = [Convert]::FromBase64String((Get-Content $b64 -Raw))
    [System.IO.File]::WriteAllBytes($unpackPy, $bytes)
    # Symlink creation is not permitted without developer mode on Windows.
    $text = [System.IO.File]::ReadAllText($unpackPy)
    $text = $text.Replace('os.symlink(src_pathname, dst_pathname)', 'pass  # symlinks are not required here')
    [System.IO.File]::WriteAllText($unpackPy, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Pull-FromDevice {
    $slot = (& adb shell getprop ro.boot.slot_suffix).Trim()
    if ([string]::IsNullOrWhiteSpace($slot)) { $slot = '_b' }
    Write-Host "[INFO] Pulling boot$slot and vendor_boot$slot from device"
    & adb shell "su -c 'dd if=/dev/block/by-name/boot$slot of=/data/local/tmp/plc110_boot.img bs=1M'" | Out-Null
    & adb shell "su -c 'dd if=/dev/block/by-name/vendor_boot$slot of=/data/local/tmp/plc110_vendor_boot.img bs=1M'" | Out-Null
    & adb pull /data/local/tmp/plc110_boot.img (Join-Path $tmpDir 'boot.img') | Out-Null
    & adb pull /data/local/tmp/plc110_vendor_boot.img (Join-Path $tmpDir 'vendor_boot.img') | Out-Null
    & adb shell "su -c 'rm -f /data/local/tmp/plc110_boot.img /data/local/tmp/plc110_vendor_boot.img'" | Out-Null
    return @((Join-Path $tmpDir 'boot.img'), (Join-Path $tmpDir 'vendor_boot.img'))
}

function Download-Images {
    Write-Host "[INFO] Downloading stock images from $StockUrl"
    $boot = Join-Path $tmpDir 'boot.img'
    $vendor = Join-Path $tmpDir 'vendor_boot.img'
    & curl.exe -fL "$StockUrl/boot.img" -o $boot
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download boot.img' }
    & curl.exe -fL "$StockUrl/vendor_boot.img" -o $vendor
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download vendor_boot.img' }
    return @($boot, $vendor)
}

if (-not $BootImg -or -not $VendorBootImg) {
    $localBoot = Join-Path $stockDir 'boot.img'
    $localVendor = Join-Path $stockDir 'vendor_boot.img'
    if ((Test-Path $localBoot) -and (Test-Path $localVendor)) {
        $BootImg = $localBoot
        $VendorBootImg = $localVendor
    } elseif ($Download) {
        $pair = Download-Images
        $BootImg, $VendorBootImg = $pair
    } elseif ($FromDevice -or (Get-Command adb -ErrorAction SilentlyContinue)) {
        $pair = Pull-FromDevice
        $BootImg, $VendorBootImg = $pair
    } else {
        $pair = Download-Images
        $BootImg, $VendorBootImg = $pair
    }
}

foreach ($f in @($BootImg, $VendorBootImg)) {
    if (-not (Test-Path $f)) { throw "Missing image: $f" }
}

Get-UnpackBootimg

$bootOut = Join-Path $tmpDir 'boot'
$vendorOut = Join-Path $tmpDir 'vendor_boot'
& $python $unpackPy --boot_img $BootImg --out $bootOut --format mkbootimg | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to unpack boot.img' }
& $python $unpackPy --boot_img $VendorBootImg --out $vendorOut --format mkbootimg | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to unpack vendor_boot.img' }

Copy-Item (Join-Path $bootOut 'kernel') (Join-Path $prebuiltDir 'kernel') -Force
Copy-Item (Join-Path $vendorOut 'dtb') (Join-Path $prebuiltDir 'dtb') -Force

# The kernel modules, the touch firmware and the first stage fstab live in the
# factory PLATFORM ramdisk; they are repacked into our own PLATFORM fragment
# instead of shipping the 40 MB factory one (see README).
$ramdiskDir = Join-Path $prebuiltDir 'ramdisk'
if (Test-Path $ramdiskDir) { Remove-Item -Recurse -Force $ramdiskDir }
& $python (Join-Path $PSScriptRoot 'extract_ramdisk_files.py') `
    --ramdisk (Join-Path $vendorOut 'vendor_ramdisk00') --dest $ramdiskDir
if ($LASTEXITCODE -ne 0) { throw 'Failed to extract the ramdisk files' }

Remove-Item -Recurse -Force $tmpDir
Write-Host "[INFO] Prebuilts written to $prebuiltDir"
Get-ChildItem $prebuiltDir | Where-Object { $_.Name -in @('kernel','dtb') } |
    Select-Object Name, Length
Get-ChildItem $ramdiskDir | Select-Object FullName