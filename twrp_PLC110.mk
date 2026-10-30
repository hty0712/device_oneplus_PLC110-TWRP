# TWRP product configuration for OnePlus Ace 5 Ultra (PLC110)

DEVICE_PATH := device/oneplus/PLC110

# Inherit common TWRP configuration first
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)
$(call inherit-product, vendor/twrp/config/common.mk)

# Device configuration
$(call inherit-product, $(DEVICE_PATH)/device.mk)

PRODUCT_DEVICE := PLC110
PRODUCT_NAME := twrp_PLC110
PRODUCT_BRAND := OnePlus
PRODUCT_MODEL := PLC110
PRODUCT_MANUFACTURER := OnePlus
PRODUCT_RELEASE_NAME := PLC110