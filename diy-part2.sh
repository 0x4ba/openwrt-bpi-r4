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

# Fix QModem Simcom driver builds on newer OpenWrt kernels where
# -Werror=missing-prototypes is enabled.
simcom_qmi_driver="feeds/qmodem/driver/simcom_QMI_WWAN/src/qmi_wwan_s.c"
if [ -f "$simcom_qmi_driver" ] && ! grep -q 'static struct sk_buff \*qmi_wwan_tx_fixup' "$simcom_qmi_driver"; then
    grep -q '^struct sk_buff \*qmi_wwan_tx_fixup(struct usbnet \*dev, struct sk_buff \*skb, gfp_t flags)' "$simcom_qmi_driver" || {
        echo "Failed to find qmi_wwan_tx_fixup in $simcom_qmi_driver" >&2
        exit 1
    }
    sed -i 's/^struct sk_buff \*qmi_wwan_tx_fixup(struct usbnet \*dev, struct sk_buff \*skb, gfp_t flags)/static struct sk_buff *qmi_wwan_tx_fixup(struct usbnet *dev, struct sk_buff *skb, gfp_t flags)/' "$simcom_qmi_driver"
    grep -q 'static struct sk_buff \*qmi_wwan_tx_fixup' "$simcom_qmi_driver" || {
        echo "Failed to patch $simcom_qmi_driver for missing-prototypes build error" >&2
        exit 1
    }
fi

# =====================================================================
# Make QModem default to ubus mode so it shares the TTY with
# at-webserver instead of competing for direct serial access.
# =====================================================================

# luci-app-qmodem (classic)
qmodem_lua="feeds/qmodem/luci/luci-app-qmodem/luasrc/model/cbi/qmodem/dial_config.lua"
if [ -f "$qmodem_lua" ]; then
    sed -i 's/use_ubus.default = "0"/use_ubus.default = "1"/' "$qmodem_lua"
    grep -q 'use_ubus.default = "1"' "$qmodem_lua" 2>/dev/null && \
        echo "QModem (classic): use_ubus defaults to 1"
fi

# luci-app-qmodem-next (JS)
for jsfile in \
    "feeds/qmodem/luci/luci-app-qmodem-next/htdocs/luci-static/resources/view/qmodem/settings.js" \
    "feeds/qmodem/luci/luci-app-qmodem-next/htdocs/luci-static/resources/view/qmodem/network_config.js"; do
    if [ -f "$jsfile" ]; then
        sed -i "s/o.default = '0'/o.default = '1'/" "$jsfile"
        grep -q "o.default = '1'" "$jsfile" 2>/dev/null && \
            echo "QModem (next): use_ubus defaults to 1 in $(basename $jsfile)"
    fi
done

# =====================================================================
# WiFi fix for BPI-R4 MT7925
# =====================================================================
# In OpenWrt main branch the wifi config script migrated from
# mac80211.sh (shell) to mac80211.uc (ucode) in the wifi-scripts
# package.  The ucode file hardcodes country = '00' for 6 GHz bands,
# which is an invalid ISO 3166-1 code.  hostapd refuses to start with
# it, so the AP never comes up.  Change the fallback to 'AU' (or any
# valid country code).

mac80211_uc="package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$mac80211_uc" ] && ! grep -q "country = 'AU'" "$mac80211_uc"; then
    sed -i "s/country = '00'/country = 'AU'/" "$mac80211_uc"
    if grep -q "country = 'AU'" "$mac80211_uc"; then
        echo "Patched $mac80211_uc: country '00' -> 'AU'"
    else
        # Fallback: try double-quote variant
        sed -i 's/country = "00"/country = "AU"/' "$mac80211_uc"
        echo "Patched $mac80211_uc (double quotes): country '00' -> 'AU'"
    fi
fi

# =====================================================================
# Fix MT7925 firmware crash — download newer firmware from linux-firmware
# =====================================================================
# The built-in MT7925 firmware (Dec 2023) is incompatible with kernel 6.18+,
# causing "Message 00020002 (seq N) timeout" when runtime-pm tries to wake
# the card from deep sleep.  Download the latest firmware from the
# linux-firmware repository to resolve compatibility.
#
# Ref: https://forum.openwrt.org/t/mt7925-crashes-in-ap-mode/231946
# Ref: https://github.com/openwrt/mt76/issues/1036

MTK_FW_DIR="package/kernel/mt76/src/firmware"
FW_BASE_URL="https://raw.githubusercontent.com/openwrt-mirror/linux-firmware/main/mediatek/mt7925"
if [ -d "$MTK_FW_DIR" ]; then
    echo "Downloading updated MT7925 firmware from linux-firmware ..."
    fw_ok=true

    curl -sSL --retry 3 --connect-timeout 10 \
        -o "$MTK_FW_DIR/WIFI_RAM_CODE_MT7925_1_1.bin" \
        "$FW_BASE_URL/WIFI_RAM_CODE_MT7925_1_1.bin" || fw_ok=false

    curl -sSL --retry 3 --connect-timeout 10 \
        -o "$MTK_FW_DIR/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin" \
        "$FW_BASE_URL/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin" || fw_ok=false

    if $fw_ok; then
        echo "OK: MT7925 firmware updated from linux-firmware"
    else
        echo "WARNING: Failed to download MT7925 firmware update (build continues with bundled firmware)"
    fi
else
    echo "WARNING: $MTK_FW_DIR not found — cannot update MT7925 firmware"
fi

# =====================================================================
# Disable MT7925 runtime-pm at boot — prevents firmware wake-up crash
# =====================================================================
# runtime-pm (runtime power management) puts the MT7925 into deep sleep
# after a period of inactivity.  With old firmware, waking it causes a
# "Message 00020002 timeout" that stalls the entire wireless stack.
# This init script disables runtime-pm at boot as a safety measure.

mkdir -p package/base-files/files/etc/init.d

cat > package/base-files/files/etc/init.d/disable-mt7925-pm << 'PMEOF'
#!/bin/sh /etc/rc.common

START=99

boot() {
    start
}

reload() {
    start
}

start() {
    # Ensure debugfs is mounted
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    # Disable runtime-pm on every mt76 phy found
    for d in /sys/kernel/debug/ieee80211/phy*/mt76; do
        [ -f "$d/runtime-pm" ] && echo 0 > "$d/runtime-pm" 2>/dev/null
    done
}
PMEOF
chmod +x package/base-files/files/etc/init.d/disable-mt7925-pm
echo "Created /etc/init.d/disable-mt7925-pm — disables mt76 runtime-pm at boot"
