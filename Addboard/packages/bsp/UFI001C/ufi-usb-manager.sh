#!/usr/bin/env sh
# ==============================================================================
# USB Gadget & Network Mode Manager for MSM8916 Dongles (e.g. UFI001C)
# Features:
#   - USB Role & Mode Auto-switching (NCM / RNDIS / ADB FunctionFS)
#   - Windows 11 Native NCM Support
#   - Automatic Fallback to Rescue AP when disconnected
# ==============================================================================

set -u

# --- 全局基础配置 (可通过环境变量覆盖) ---
GADGET_CONTROL=${GADGET_CONTROL:-"/usr/bin/gc"}
FAILSAFE_AP_CON=${FAILSAFE_AP_CON:-"UFI001C-AP"}
FAILSAFE_AP_SSID=${FAILSAFE_AP_SSID:-"UFI001C-AP"}
FAILSAFE_AP_PASSWORD=${FAILSAFE_AP_PASSWORD:-"00000000"}
FAILSAFE_AP_CHANNEL=${FAILSAFE_AP_CHANNEL:-"6"}
FAILSAFE_AP_ADDRESS=${FAILSAFE_AP_ADDRESS:-"192.168.5.1/24"}
GC_MODE=${GC_MODE:-"ncm,ffs"}
USB_CON_NAME="USB-UFI001C"
LOG_TAG="ufi-manager"

unset LANGUAGES
export LANG=C

# --- Sysfs / Debugfs 节点路径 ---
SYS_ROLE_SWITCH="/sys/class/usb_role/ci_hdrc.0-role-switch/role"
UDC_SYSFS="/sys/class/udc/ci_hdrc.0"
USB_DEBUG_DIR="/sys/kernel/debug/usb/ci_hdrc.0"
USB_DEBUG_ROLE="$UDC_SYSFS/device/role"
USB_DEBUG_ROLE_ALT="$USB_DEBUG_DIR/role"
USB_REGISTER_DEBUG="$USB_DEBUG_DIR/registers"

# --- 统一日志输出 ---
log() {
  logger -t "$LOG_TAG" "$*"
}

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
  log "Changing USB from $CURRENT_USB_ROLE mode to $TARGET_ROLE mode"
  
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
    log "Error: Neither USB Role Switch nor debugfs role node found!"
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

  HEX_VAL=$(awk '/^PORTSC.*/{print $3; exit}' "${USB_REGISTER_DEBUG}" 2>/dev/null)
  if [ -n "$HEX_VAL" ] && [ "$HEX_VAL" != "0x" ]; then
    case "$HEX_VAL" in
      0x*|0X*) ;;
      *) HEX_VAL="0x$HEX_VAL" ;;
    esac
    
    # 严格校验十六进制合法性，防止 dash 抛出算术解析错误
    CLEAN_HEX=$(echo "${HEX_VAL#0x}" | tr -d '0-9a-fA-F')
    if [ -z "$CLEAN_HEX" ]; then
    if [ $((HEX_VAL & 0x80)) -eq 0 ] && [ $((HEX_VAL & 0x4)) -ne 0 ]; then
      return 0
      fi
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
  ACTIVE_WIFI=$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | \
    awk -F: -v ap="$FAILSAFE_AP_CON" '$2 ~ /^(802-11-wireless|wifi)$/ && $3 == "connected" && $4 != ap {print $4}')
  [ -n "$ACTIVE_WIFI" ]
}

is_ethernet_connected() {
  nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -E "^(eth|end|enp)[0-9a-zA-Z]+:ethernet:connected$" >/dev/null
}

setup_usb_network_profile() {
  # 适配 ncm / rndis / ecm 的网络共享配置
  case "$GC_MODE" in
    *ncm*|*rndis*|*ecm*)
      if ! nmcli connection show "$USB_CON_NAME" >/dev/null 2>&1; then
        log "Creating NetworkManager USB profile ($USB_CON_NAME) with Shared IPv4"
        nmcli connection add type ethernet ifname usb0 con-name "$USB_CON_NAME" ipv4.method shared >/dev/null 2>&1 || true
      fi
      nmcli --wait 5 connection up "$USB_CON_NAME" >/dev/null 2>&1 || true
      ;;
  esac
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
  "$GADGET_CONTROL" -d >/dev/null 2>&1 || true
  "$GADGET_CONTROL" -c >/dev/null 2>&1 || true
  
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

        if [ -x /usr/bin/adbd ]; then
          nohup /usr/bin/adbd >/dev/null 2>&1 &
        fi
        DELAY=1
        ;;
      mass*)
        "$GADGET_CONTROL" -a "$i"
        ;;
      *)
        log "Unsupported USB function provided: $i"
        ;;
    esac
  done
  set +f
  IFS="$OLD_IFS"

  if [ "$DELAY" -ne 0 ]; then
    log "Waiting for USB services (e.g. adbd)..."
    sleep 2
  fi
  "$GADGET_CONTROL" -e >/dev/null 2>&1 || true
  
  setup_usb_network_profile
}

setup_failsafe_ap() {
  log "Preparing Failsafe AP..."

  # 1. 解锁 WiFi 射频并配置频段国家代码
  iw reg set CN 2>/dev/null || true
  rfkill unblock wifi 2>/dev/null || true

  # 2. 等待 wlan0 接口生成
  WAIT_WLAN=10
  while [ "$WAIT_WLAN" -gt 0 ]; do
    if ip link show wlan0 >/dev/null 2>&1; then
      break
    fi
    log "Waiting for wlan0 interface..."
    sleep 1
    WAIT_WLAN=$((WAIT_WLAN - 1))
  done

  if ! ip link show wlan0 >/dev/null 2>&1; then
    log "Error: wlan0 interface not found after 10s!"
    return 1
  fi

  # 3. 创建静态 AP 配置
  if ! nmcli connection show "$FAILSAFE_AP_CON" >/dev/null 2>&1; then
    log "Creating Failsafe AP profile..."
    nmcli connection add \
      type wifi ifname wlan0 con-name "$FAILSAFE_AP_CON" \
      ssid "$FAILSAFE_AP_SSID" \
      autoconnect no \
      ipv4.addresses "$FAILSAFE_AP_ADDRESS" \
      ipv4.method shared \
      wifi.mode ap \
      wifi.band bg wifi.channel "$FAILSAFE_AP_CHANNEL" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.proto rsn \
      wifi-sec.pairwise ccmp \
      wifi-sec.group ccmp \
      wifi-sec.pmf 1 \
      wifi-sec.psk "$FAILSAFE_AP_PASSWORD" >/dev/null 2>&1
  fi
  
  log "Starting Failsafe AP ($FAILSAFE_AP_SSID)..."
  nmcli connection up "$FAILSAFE_AP_CON" 2>&1 | logger -t "$LOG_TAG"
}

# ================= 启动调度逻辑 =================
startup() {
  # 1. 等待 NetworkManager 完全就绪 (最多 10 秒)
  WAIT_NM=10
  while [ "$WAIT_NM" -gt 0 ]; do
    if nmcli general status >/dev/null 2>&1; then
      break
    fi
    sleep 1
    WAIT_NM=$((WAIT_NM - 1))
  done

  # 2. 初始化 USB Gadget 模式
  if [ -n "${GC_MODE}" ]; then
    log "Setting up gadgets: $GC_MODE"
    if ! setup_gadget_mode; then
      log "Cannot activate gadget mode, host mode detected"
    fi
  else
    if ! is_usb_connected; then
      set_usb_host_mode
    fi
  fi
  
  # 3. 检查是否插在 PC 上并完成了 USB 枚举
  sleep 2
  UDC_STATE=$(cat "${UDC_SYSFS}/state" 2>/dev/null)
  if is_gadget_mode && [ "$UDC_STATE" = "configured" ]; then
    log "Device is connected to PC (USB: configured). Gadget mode active."
    return 0
  fi

  # 4. 开机检测家庭 WiFi 或 Ethernet (25 秒窗口)
  log "Waiting for Home WiFi/Ethernet uplink..."
  WAIT_TIME=25
  while [ "$WAIT_TIME" -gt 0 ]; do
    if is_client_wifi_connected || is_ethernet_connected; then
      log "Connected to Home WiFi/Ethernet. Client mode active."
      return 0
    fi
    sleep 2
    WAIT_TIME=$((WAIT_TIME - 2))
  done

  # 5. 无任何可用网络，启动应急救援 AP
  log "No uplink detected. Starting Failsafe AP..."
  setup_failsafe_ap
}

case "${1:-}" in
  startup)
    startup
    ;;
  *)
    log "Invalid or missing action: ${1:-none}"
    exit 1
    ;;
esac