#!/usr/bin/env sh
## A smart usb gadget & network auto-switching manager for MSM8916 (UFI001C)

# 基础配置
GADGET_CONTROL=${GADGET_CONTROL:-"/usr/bin/gc"}
WIFI_IFACE=${WIFI_IFACE:-"wlan0"}
FAILSAFE_AP_CON=${FAILSAFE_AP_CON:-"UFI001C-AP"}
FAILSAFE_AP_SSID=${FAILSAFE_AP_SSID:-"UFI001C-AP"}
FAILSAFE_AP_PASSWORD=${FAILSAFE_AP_PASSWORD:-"00000000"}
FAILSAFE_AP_CHANNEL=${FAILSAFE_AP_CHANNEL:-"6"}
FAILSAFE_AP_ADDRESS=${FAILSAFE_AP_ADDRESS:-"192.168.5.1/24"}
GC_MODE=${GC_MODE:-""}
USBNET_CON_NAME="USB-UFI001C"
LOG_TAG="ufi-manager"

# 时间策略（单位：秒）
PROBE_INTERVAL=120      # AP 状态下，每隔 2 分钟巡检一次家里 WiFi

unset LANGUAGES
export LANG=C

trap 'log "Service stopping..."; exit 0' TERM INT

SYS_ROLE_SWITCH="/sys/class/usb_role/ci_hdrc.0-role-switch/role"
UDC_SYSFS="/sys/class/udc/ci_hdrc.0"
USB_DEBUG_DIR="/sys/kernel/debug/usb/ci_hdrc.0"
USB_DEBUG_ROLE="$UDC_SYSFS/device/role"
USB_DEBUG_ROLE_ALT="$USB_DEBUG_DIR/role"
USB_REGISTER_DEBUG="$USB_DEBUG_DIR/registers"

log() {
  logger -t "$LOG_TAG" "$@"
}

get_usb_role() {
  if [ -f "${SYS_ROLE_SWITCH}" ]; then
    CURRENT=$(cat "${SYS_ROLE_SWITCH}" 2>/dev/null)
    [ "$CURRENT" = "device" ] && echo "gadget" || echo "$CURRENT"
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
  [ "$TARGET_ROLE" = "$CURRENT_USB_ROLE" ] && return 0
  log "Changing USB from $CURRENT_USB_ROLE to $TARGET_ROLE mode"

  if [ -f "${SYS_ROLE_SWITCH}" ]; then
    [ "$TARGET_ROLE" = "gadget" ] && echo "device" > "${SYS_ROLE_SWITCH}" || echo "$TARGET_ROLE" > "${SYS_ROLE_SWITCH}"
  elif [ -f "${USB_DEBUG_ROLE}" ]; then
    echo "$TARGET_ROLE" > "${USB_DEBUG_ROLE}"
  elif [ -f "${USB_DEBUG_ROLE_ALT}" ]; then
    echo "$TARGET_ROLE" > "${USB_DEBUG_ROLE_ALT}"
  else
    log "Error: USB Role Switch node not found!"
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

# 检查是否连上除救援 AP 外的正常 WiFi
is_client_wifi_connected() {
  ACTIVE_WIFI=$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | \
    awk -F: -v ap="$FAILSAFE_AP_CON" '$2 ~ /^(802-11-wireless|wifi)$/ && $3 == "connected" && $4 != ap {print $4}')
  [ -n "$ACTIVE_WIFI" ]
}

# 检查是否连上有线网
is_ethernet_connected() {
  nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -E "^(eth|end|enp)[0-9a-zA-Z]+:ethernet:connected$" >/dev/null
}

# 检查当前是否正发射救援 AP
is_ap_active() {
  nmcli -t -f CONNECTION,STATE device 2>/dev/null | grep -E "^${FAILSAFE_AP_CON}:connected$" >/dev/null
}

# 检查是否有客户端连接在 AP 上
has_ap_clients() {
  iw dev "${WIFI_IFACE}" station dump 2>/dev/null | grep -q "Station"
}

# 配置 USB 虚拟网卡 (支持 rndis, ncm, ecm)
setup_usb_net_profile() {
  if echo "$GC_MODE" | grep -Eq "rndis|ncm|ecm"; then
    if ! nmcli connection show "$USBNET_CON_NAME" >/dev/null 2>&1; then
      log "Creating NetworkManager USB Net profile ($USBNET_CON_NAME)"
      nmcli connection add type ethernet ifname usb0 con-name "$USBNET_CON_NAME" ipv4.method shared >/dev/null 2>&1 || true
    fi
    nmcli --wait 5 connection up "$USBNET_CON_NAME" >/dev/null 2>&1 || true
  fi
}

setup_gadget_mode() {
  if is_host_mode && is_usb_connected; then
    return 1
  fi
  [ -z "$GC_MODE" ] && return 1

  set_usb_mode "gadget"

  DELAY=0
  "$GADGET_CONTROL" -d 
  "$GADGET_CONTROL" -c
  
  OLD_IFS="$IFS"
  IFS=","
  set -f
  for i in $GC_MODE; do
    case "$i" in
      serial|hid|midi|printer|uvc|rndis|ecm|acm|ncm)
        "$GADGET_CONTROL" -a "$i"
        ;;
      ffs)
        killall adbd 2>/dev/null || pkill -x adbd 2>/dev/null || true
        umount /dev/usb-ffs/adb 2>/dev/null || true
        "$GADGET_CONTROL" -a ffs
        mkdir -p /dev/usb-ffs/adb
        if ! mountpoint -q /dev/usb-ffs/adb; then
          mount -t functionfs adb /dev/usb-ffs/adb 2>/dev/null || true
        fi
        [ -x /usr/bin/adbd ] && /usr/bin/adbd &
        DELAY=1
        ;;
      mass*)
        "$GADGET_CONTROL" -a "$i"
        ;;
      *)
        log "Unsupported USB function: $i"
        ;;
    esac
  done
  set +f
  IFS="$OLD_IFS"

  if [ "$DELAY" -ne 0 ]; then
    log "Waiting for USB services to ready..."
    sleep 3
  fi
  "$GADGET_CONTROL" -e 
  setup_usb_net_profile
}

setup_failsafe_ap() {
  log "Starting Failsafe AP..."
  iw reg set CN 2>/dev/null || true
  rfkill unblock wifi 2>/dev/null || true

  # 确保网卡存在
  WAIT_WLAN=10
  while [ "$WAIT_WLAN" -gt 0 ]; do
    ip link show "${WIFI_IFACE}" >/dev/null 2>&1 && break
    sleep 1
    WAIT_WLAN=$((WAIT_WLAN - 1))
  done
  [ "$WAIT_WLAN" -eq 0 ] && { log "Error: ${WIFI_IFACE} not found!"; return 1; }

  # 给驱动 1 秒重置状态，防止 wcn36xx 报错
  sleep 1

  if ! nmcli connection show "$FAILSAFE_AP_CON" >/dev/null 2>&1; then
    log "Creating Failsafe AP profile..."
    nmcli connection add \
      type wifi ifname "${WIFI_IFACE}" con-name "$FAILSAFE_AP_CON" \
      ssid "$FAILSAFE_AP_SSID" autoconnect no \
      ipv4.addresses "$FAILSAFE_AP_ADDRESS" \
      ipv4.method shared \
      wifi.mode ap wifi.band bg wifi.channel "$FAILSAFE_AP_CHANNEL" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.proto rsn \
      wifi-sec.pairwise ccmp \
      wifi-sec.group ccmp \
      wifi-sec.pmf 1 \
      wifi-sec.psk "$FAILSAFE_AP_PASSWORD" >/dev/null 2>&1
  fi
  
  nmcli connection up "$FAILSAFE_AP_CON" 2>&1 | logger -t "$LOG_TAG"
}

# ================= 核心改进：主动依次连接所有已保存的家里 WiFi =================
try_connect_saved_wifis() {
  # 如果已有有线网，直接判定成功
  if is_ethernet_connected; then
    return 0
  fi

  # 唤醒网卡
  rfkill unblock wifi 2>/dev/null || true
  nmcli device set "${WIFI_IFACE}" managed yes 2>/dev/null || true
  nmcli device wifi rescan 2>/dev/null || true
  sleep 1

  # 获取所有除救援 AP 以外的已保存 Wi-Fi 连接 UUID
  AP_UUID=$(nmcli -g UUID,NAME connection show 2>/dev/null | awk -F: -v ap="$FAILSAFE_AP_CON" '$2 == ap {print $1}')
  SAVED_UUIDS=$(nmcli -g UUID,TYPE connection show 2>/dev/null | awk -F: -v ap_uuid="$AP_UUID" '$2 ~ /^(802-11-wireless|wifi)$/ && $1 != ap_uuid {print $1}')

  [ -z "$SAVED_UUIDS" ] && return 1

  for uuid in $SAVED_UUIDS; do
    [ -z "$uuid" ] && continue
    log "Actively attempting to connect to saved WiFi (UUID: $uuid)..."
    # 主动发起连接，给 8 秒超时窗口
    if nmcli --wait 8 connection up uuid "$uuid" >/dev/null 2>&1; then
      log "Successfully connected to WiFi (UUID: $uuid)!"
      return 0
    fi
  done

  return 1
}

# ================= 后台看门狗守护巡检 =================
run_watchdog() {
  log "Watchdog started: Auto-switching between Home WiFi and AP enabled."
  
  while true; do
    sleep "$PROBE_INTERVAL"

    # 如果已经在正常上网，继续休眠
    if is_client_wifi_connected || is_ethernet_connected; then
      continue
    fi

    # 如果当前处于 AP 状态
    if is_ap_active; then
      # 如果有用户连着 AP，不打扰用户
      if has_ap_clients; then
        log "Active clients connected to AP. Skip probing."
        continue
      fi

      log "No clients on AP. Temporarily stopping AP to probe Home WiFi..."
      nmcli connection down "$FAILSAFE_AP_CON" >/dev/null 2>&1 || true
      sleep 2
    fi

    # 主动尝试连接已保存的 WiFi
    if try_connect_saved_wifis; then
      log "Successfully switched to Home WiFi! Staying in Client Mode."
    else
      log "Home WiFi still unavailable. Re-activating Failsafe AP..."
      setup_failsafe_ap
    fi
  done
}

# ================= 主启动入口 =================
startup() {
  # 1. 等待 NetworkManager 完全就绪
  WAIT_NM=15
  while [ "$WAIT_NM" -gt 0 ]; do
    nmcli general status >/dev/null 2>&1 && break
    sleep 1
    WAIT_NM=$((WAIT_NM - 1))
  done

  # 2. 初始化 USB 功能
  if [ -n "${GC_MODE}" ]; then
    log "Setting up gadgets: $GC_MODE"
    setup_gadget_mode || true
  else
    is_usb_connected || set_usb_host_mode
  fi

  # 3. 开机直接主动尝试连接家里已保存的 WiFi
  log "Probing Home WiFi at boot..."
  if try_connect_saved_wifis; then
    log "Connected to Home WiFi at boot! Client mode ACTIVE."
  else
    log "Home WiFi not available. Launching Failsafe AP..."
    setup_failsafe_ap
  fi

  # 4. 启动后台看门狗守护
  run_watchdog
}

case "$1" in
  startup)
    startup
    ;;
  *)
    log "Usage: $0 startup"
    ;;
esac