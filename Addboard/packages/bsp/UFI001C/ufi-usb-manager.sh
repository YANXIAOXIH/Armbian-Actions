#!/usr/bin/env sh
## A usb gadget manager for MSM8916 based usb dongles

GADGET_CONTROL=${GADGET_CONTROL:-"/usr/bin/gc"}
FAILSAFE_AP_CON=${FAILSAFE_AP_CON:-"UFI001C-AP"}
FAILSAFE_AP_SSID=${FAILSAFE_AP_SSID:-"UFI001C-AP"}
FAILSAFE_AP_PASSWORD=${FAILSAFE_AP_PASSWORD:-"00000000"}
FAILSAFE_AP_CHANNEL=${FAILSAFE_AP_CHANNEL:-"6"}
FAILSAFE_AP_ADDRESS=${FAILSAFE_AP_ADDRESS:-"192.168.5.1/24"}
GC_MODE=${GC_MODE-""}
RNDIS_CON_NAME="USB-UFI001C"

unset LANGUAGES
export LANG=C

SYS_ROLE_SWITCH="/sys/class/usb_role/ci_hdrc.0-role-switch/role"
UDC_SYSFS="/sys/class/udc/ci_hdrc.0"
USB_DEBUG_DIR="/sys/kernel/debug/usb/ci_hdrc.0"
USB_DEBUG_ROLE="$UDC_SYSFS/device/role"
USB_DEBUG_ROLE_ALT="$USB_DEBUG_DIR/role"
USB_REGISTER_DEBUG="$USB_DEBUG_DIR/registers"

get_usb_role() {
  if [ -f "${SYS_ROLE_SWITCH}" ]; then
    CURRENT=$(cat "${SYS_ROLE_SWITCH}" 2>/dev/null)
    if [ "$CURRENT" = "device" ]; then
      echo "gadget"
    else
      echo "$CURRENT"
    fi
  elif [ -f "${USB_DEBUG_ROLE}" ]; then
    cat "${USB_DEBUG_ROLE}" 2>/dev/null || echo "unknown"
  elif [ -f "${USB_DEBUG_ROLE_ALT}" ]; then
    cat "${USB_DEBUG_ROLE_ALT}" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
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

  if [ -f "${SYS_ROLE_SWITCH}" ]; then
    if [ "$TARGET_ROLE" = "gadget" ]; then
      echo "device" > "${SYS_ROLE_SWITCH}"
    else
      echo "$TARGET_ROLE" > "${SYS_ROLE_SWITCH}"
    fi
    return $?
  elif [ -f "${USB_DEBUG_ROLE}" ]; then
    echo "$TARGET_ROLE" > "${USB_DEBUG_ROLE}"
    return $?
  elif [ -f "${USB_DEBUG_ROLE_ALT}" ]; then
    echo "$TARGET_ROLE" > "${USB_DEBUG_ROLE_ALT}"
    return $?
  else
    logger "Error: Neither USB Role Switch nor debugfs role node found!"
    return 1
  fi
}

set_usb_host_mode() {
  set_usb_mode "host"
}

is_usb_host_connected_sysfs() {
  for dev in /sys/bus/usb/devices/*; do
    [ -e "$dev" ] || continue
    case "$(basename "$dev")" in
      usb[0-9]*|*-0:*) ;;
      *:*) ;;
      "") ;;
      *) return 0 ;;
    esac
  done
  return 1
}

#is_usb_connected_legacy() {
#  if [ ! -f "${USB_REGISTER_DEBUG}" ]; then
#    return 1
#  fi
#  CMP_VALUE=$(gawk '/^PORTSC.*/{ a = strtonum("0x" $3); exit } END { b = and(a, 0x4); c = and(a, 0x80); if (c == 0) { print b } else { print 0 }  }' "${USB_REGISTER_DEBUG}")
#  
#  [ "$CMP_VALUE" -ne 0 ]
#}

is_usb_connected_legacy() {
  [ -f "${USB_REGISTER_DEBUG}" ] || return 1

  HEX_VAL=$(awk '/^PORTSC.*/{print $3; exit}' "${USB_REGISTER_DEBUG}")
  if [ -n "$HEX_VAL" ]; then
    HEX_VAL="0x${HEX_VAL#0x}"
    if [ $((HEX_VAL & 0x80)) -eq 0 ] && [ $((HEX_VAL & 0x4)) -ne 0 ]; then
      return 0
    fi
  fi
  return 1
}

is_usb_connected() {
  if is_gadget_mode; then
    [ "configured" = "$(cat "${UDC_SYSFS}/state" 2>/dev/null)" ]
  elif is_host_mode; then
    is_usb_host_connected_sysfs || is_usb_connected_legacy
  else
    return 1
  fi
}

is_client_wifi_connected() {
  ACTIVE_WIFI_CON=$(nmcli -t -f TYPE,NAME connection show --active 2>/dev/null | grep -E "^(802-11-wireless|wifi):" | cut -d: -f2)
  if [ -n "$ACTIVE_WIFI_CON" ] && [ "$ACTIVE_WIFI_CON" != "$FAILSAFE_AP_CON" ]; then
    return 0
  fi
  return 1
}

is_ethernet_connected() {
  nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -E "^(eth|end|enp)[0-9a-zA-Z]+:ethernet:connected$" >/dev/null
}

setup_rndis_profile() {
  if echo "$GC_MODE" | grep -q "rndis"; then
    if ! nmcli connection show "$RNDIS_CON_NAME" >/dev/null 2>&1; then
      logger "Creating NetworkManager RNDIS profile ($RNDIS_CON_NAME)"
      nmcli connection add type ethernet ifname usb0 con-name "$RNDIS_CON_NAME" ipv4.method shared >/dev/null 2>&1 || true
    fi
    nmcli --wait 5 connection up "$RNDIS_CON_NAME" >/dev/null 2>&1 || true
  fi
}

setup_gadget_mode() {
  if is_host_mode && is_usb_connected; then
    return 1
  fi

  if [ -z "$GC_MODE" ]; then
    return 1
  fi

  set_usb_mode "gadget"

  DELAY=0
  "$GADGET_CONTROL" -d 
  "$GADGET_CONTROL" -c
  
  for i in $(echo "${GC_MODE}" | sed "s/,/ /g"); do
    case "$i" in
      serial|hid|midi|printer|uvc|rndis|ecm|acm)
        "$GADGET_CONTROL" -a "$i"
        ;;
      ffs)
        killall adbd 2>/dev/null || pkill -x adbd 2>/dev/null || true
        umount /dev/usb-ffs/adb 2>/dev/null || true

        "$GADGET_CONTROL" -a ffs
        mkdir -p /dev/usb-ffs/adb
        mount -t functionfs adb /dev/usb-ffs/adb 2>/dev/null || true

        if [ -x /usr/bin/adbd ]; then
          /usr/bin/adbd &
        fi
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
    sleep 3
  fi
  "$GADGET_CONTROL" -e 
  
  setup_rndis_profile
}

setup_failsafe_ap() {
  if ! nmcli connection show "$FAILSAFE_AP_CON" >/dev/null 2>&1; then
    logger "Creating Failsafe AP profile..."
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
  fi
  logger "Starting Failsafe AP..."
  nmcli connection up "$FAILSAFE_AP_CON" >/dev/null
}

startup() {
  if [ -n "${GC_MODE}" ]; then
    logger "Setting up gadgets: $GC_MODE"
    if ! setup_gadget_mode; then
      logger "Cannot activate gadget mode, perhaps already connected to a host"
    fi
  else
    if ! is_usb_connected; then
      set_usb_host_mode
    fi
  fi
  
  sleep 3
  UDC_STATE=$(cat "${UDC_SYSFS}/state" 2>/dev/null)
  
  if is_gadget_mode && [ "$UDC_STATE" = "configured" ]; then
    logger "Device is connected to a PC (State: configured). RNDIS and ADB are ACTIVE."
    return 0
  fi

  logger "Checking for Home WiFi/Ethernet connection..."
  WAIT_TIME=15
  
  while [ "$WAIT_TIME" -gt 0 ]; do
    if is_client_wifi_connected || is_ethernet_connected; then
      logger "Connected to Home WiFi/Ethernet. Entering Home Server Mode (No AP needed)."
      return 0
    fi
    sleep 2
    WAIT_TIME=$((WAIT_TIME - 2))
  done

  logger "Home WiFi not detected. Starting 4G Shared / Failsafe AP..."
  setup_failsafe_ap
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