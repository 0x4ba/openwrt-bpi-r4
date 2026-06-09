#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# Fix QModem Fibocom driver builds on newer OpenWrt kernels where
# -Werror=missing-prototypes is enabled.
fibocom_qmi_driver="feeds/qmodem/driver/fibocom_QMI_WWAN/src/qmi_wwan_f.c"
if [ -f "$fibocom_qmi_driver" ] && ! grep -q 'static int qma_setting_store' "$fibocom_qmi_driver"; then
    sed -i 's/^int qma_setting_store(struct device \*dev, QMAP_SETTING \*qmap_settings, size_t size) {/static int qma_setting_store(struct device *dev, QMAP_SETTING *qmap_settings, size_t size) {/' "$fibocom_qmi_driver"
    grep -q 'static int qma_setting_store' "$fibocom_qmi_driver" || {
        echo "Failed to patch $fibocom_qmi_driver for missing-prototypes build error" >&2
        exit 1
    }
fi

# Fix QModem Quectel driver builds on Linux 6.17+ where usbnet_bh is no
# longer used but -Werror=unused-function is enabled.
quectel_qmi_driver="feeds/qmodem/driver/quectel_QMI_WWAN/src/qmi_wwan_q.c"
if [ -f "$quectel_qmi_driver" ] && ! grep -q 'static void __maybe_unused usbnet_bh' "$quectel_qmi_driver"; then
    grep -q '^static void usbnet_bh(unsigned long data) {' "$quectel_qmi_driver" || {
        echo "Failed to find usbnet_bh in $quectel_qmi_driver" >&2
        exit 1
    }
    sed -i 's/^static void usbnet_bh(unsigned long data) {/static void __maybe_unused usbnet_bh(unsigned long data) {/' "$quectel_qmi_driver"
    grep -q 'static void __maybe_unused usbnet_bh' "$quectel_qmi_driver" || {
        echo "Failed to patch $quectel_qmi_driver for unused-function build error" >&2
        exit 1
    }
fi
