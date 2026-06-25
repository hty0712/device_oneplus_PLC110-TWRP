# Copyright (C) 2023-2024 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$(call inherit-product, $(SRC_TARGET_DIR)/product/languages_full.mk)

# Inherit from common device tree
$(call inherit-product, $(LOCAL_PATH)/twrp_PLF110.mk)

PRODUCT_DEVICE := PLF110
PRODUCT_NAME := twrp_PLF110
PRODUCT_BRAND := OnePlus
PRODUCT_MODEL := Ace 5 Racing Edition
PRODUCT_MANUFACTURER := OnePlus
PRODUCT_RESTRICT_VENDOR_FILES := false
