#!/usr/bin/env sh
## A usb gadget manager for MSM8916 based usb dongles

# Change variables below in a systemd service overlay.
# command: systemctl --edit ufi-usb-manager.service

GADGET_CONTROL=${GADGET_CONTROL:-"/usr/bin/gc"}
FAILSAFE_AP_CON=${FAILSAFE_AP_CON:-"UFI001C-AP"}
FAILSAFE_AP_SSID=${FAILSAFE_AP_SSID:-"UFI001C-AP"}
FAILSAFE_AP_PASSWORD=${FAILSAFE_AP_PASSWORD:-"00000000"}
FAILSAFE_AP_CHANNEL=${FAILSAFE_AP_CHANNEL:-"3"}
FAILSAFE_AP_ADDRESS=${FAILSAFE_AP_ADDRESS:-"192.168.5.1/24"}
GC_MODE=${GC_MODE-""}

# make sure the output is English
unset LANGUAGES
export LANG=C

UDC_SYSFS="/sys/class/udc/ci_hdrc.0"
USB_DEBUG="/sys/kernel/debug/usb/ci_hdrc.0"
USB_ROLE_DEBUG="$UDC_SYSFS/device/role"
USB_REGISTER_DEBUG="$USB_DEBUG/registers"
CONFIGFS_GADGET="/sys/kernel/config/usb_gadget"

load_modules() {
  modprobe libcomposite
}

# [注意]: 此函数在原脚本中定义但从未被调用过，实际创建gadget由 /usr/bin/gc 完成。
# 保留于此仅作参考。
create_gadget() {
  rm -rf "${CONFIGFS_GADGET}/g1"  # cleanup old gadgets
  mkdir -p "${CONFIGFS_GADGET}/g1"
  echo "0x18d1" > "${CONFIGFS_GADGET}/idVendor"
  echo "0xd001" > "${CONFIGFS_GADGET}/idProduct"
  
  STRING_DIR="${CONFIGFS_GADGET}/strings/0x409"
  mkdir -p "${STRING_DIR}"
  echo "0123456789" > "${STRING_DIR}/serialnumber"
  echo "D-Works" > "${STRING_DIR}/manufacturer"
  echo "UFI001C-Gadget" > "${STRING_DIR}/product"

  CONFIG_DIR="${CONFIGFS_GADGET}/configs"
  mkdir -p "${CONFIG_DIR}/c.1"
}

get_usb_role() {
  cat "${USB_ROLE_DEBUG}" 2>/dev/null || echo "unknown"
}

is_gadget_mode() {
  [ "gadget" = "$(get_usb_role)" ]
}

is_host_mode() {
  [ "host" = "$(get_usb_role)" ]
}

set_usb_mode() {
  CURRENT_USB_ROLE=$(get_usb_role)
  TARGET_ROLE="$1"
  logger "Changing USB from $CURRENT_USB_ROLE mode to $TARGET_ROLE mode"
  if [ "$TARGET_ROLE" = "$CURRENT_USB_ROLE" ]; then
    return 0
  fi
  echo "$TARGET_ROLE" > "${USB_ROLE_DEBUG}"
  return $?
}

set_usb_gadget_mode() {
  set_usb_mode "gadget"
}

set_usb_host_mode() {
  set_usb_mode "host"
}

is_usb_connected_legacy() {
  # 依赖 gawk 进行十六进制按位与运算
  if [ ! -f "${USB_REGISTER_DEBUG}" ]; then
    return 1
  fi
  CMP_VALUE=$(gawk '/^PORTSC.*/{ a = strtonum("0x" $3); exit } END { b = and(a, 0x4); c = and(a, 0x80); if (c == 0) { print b } else { print 0 }  }' "${USB_REGISTER_DEBUG}")
  
  [ "$CMP_VALUE" -ne 0 ]
}

is_usb_connected() {
  if is_gadget_mode; then
    [ "configured" = "$(cat "${UDC_SYSFS}/state" 2>/dev/null)" ]
  elif is_host_mode; then
    is_usb_connected_legacy
  else
    return 1
  fi
}

# 使用更高效、更严谨的 nmcli 原生输出解析替代繁琐的 awk+grep 管道
is_wifi_connected() {
  nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q "^wifi:connected$"
}

is_ethernet_connected() {
  nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q "^ethernet:connected$"
}

is_usb_net_connected() {
  nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q -E "^(gsm|cdma|usb):connected$"
}

is_device_online() {
  if is_wifi_connected || is_ethernet_connected; then
    return 0
  elif is_usb_net_connected && is_gadget_mode && is_usb_connected; then
    return 0
  else
    return 1
  fi
}

setup_gadget_mode() {
  if is_host_mode && is_usb_connected; then
    return 1
  fi

  if [ -z "$GC_MODE" ]; then
    return 1
  fi

  set_usb_gadget_mode

  DELAY=0
  "$GADGET_CONTROL" -d        # disable all
  "$GADGET_CONTROL" -c        # cleanup
  
  for i in $(echo "${GC_MODE}" | sed "s/,/ /g"); do
    case "$i" in
      serial|hid|midi|printer|uvc|rndis|ecm|acm)
        "$GADGET_CONTROL" -a "$i"
        ;;
      ffs)
        "$GADGET_CONTROL" -a ffs
        mkdir -p /dev/usb-ffs/adb
        mount -t functionfs adb /dev/usb-ffs/adb 2>/dev/null || true
        systemctl start adbd
        DELAY=1
        ;;
      mass*)
        "$GADGET_CONTROL" -a "$i"
        ;;
      *)
        logger "Unsupported USB function provided: $i"
        ;;
    esac
  done

  if [ "$DELAY" -ne 0 ]; then
    logger "Delay for a while to wait some services (eg. adbd)"
    sleep 5
  fi
  "$GADGET_CONTROL" -e        # enable gadget
}

setup_failsafe_ap() {
  nmcli connection delete "$FAILSAFE_AP_CON" >/dev/null 2>&1 || true

  nmcli connection add \
    type wifi ifname wlan0 con-name "$FAILSAFE_AP_CON" \
    ssid "$FAILSAFE_AP_SSID" autoconnect no \
    ipv4.addresses "$FAILSAFE_AP_ADDRESS" \
    ipv4.method shared \
    wifi.mode ap \
    wifi.band bg wifi.channel "$FAILSAFE_AP_CHANNEL" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.proto rsn \
    wifi-sec.group ccmp wifi-sec.pairwise ccmp \
    wifi-sec.psk "$FAILSAFE_AP_PASSWORD" >/dev/null

  nmcli connection up "$FAILSAFE_AP_CON" >/dev/null
} 

setup_serial_ttyMSM0() {
  logger "Serial console activation is disabled by user."
  return 0
}

startup() {
  if ! is_usb_connected; then
    set_usb_host_mode
  fi
  
  sleep 3

  if [ -n "${GC_MODE}" ]; then
    logger "Setting up gadgets: $GC_MODE"
    if ! setup_gadget_mode; then
      logger "Cannot activate gadget mode, perhaps already connected to gadget devices as a host"
    fi
  fi
}

ACTION="$1"
case "$ACTION" in
  startup)
    startup
    ;;
  *)
    logger "Invalid action: $ACTION"
    ;;
esac