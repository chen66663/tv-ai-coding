#!/usr/bin/env bash
# 海信电视调试小工具集
#
# 用法:
#   ./tv.sh connect 192.168.1.83
#   ./tv.sh info              # 型号/系统/ABI/开机时长
#   ./tv.sh mem               # 内存概览 + TOP 进程
#   ./tv.sh cpu               # CPU 二次采样
#   ./tv.sh fps <包名> [秒数]  # 连续切焦点的真实掉帧率
#   ./tv.sh probe-codec       # 拉取并解读解码能力
#   ./tv.sh clean             # 禁用无用包（会打印每一步）
#   ./tv.sh enable <包名>     # 恢复被禁用的包
#   ./tv.sh fix-home <包名>   # 重设无障碍 + 默认桌面（覆盖安装后必跑）
#   ./tv.sh shot <输出文件>   # 截图
#
# 前置: adb 在 PATH 里；电视已 adb connect 并在电视上点了"允许"

set -u
ADB="${ADB:-adb}"
PKG_HOME="${PKG_HOME:-}"

# Git Bash 下 adb pull 的路径会被改写，统一加这个
export MSYS_NO_PATHCONV=1

need_dev() {
  if ! $ADB devices | grep -qE "^\S+\s+device$"; then
    echo "!! 没有已授权设备，先执行: $0 connect <电视IP>" >&2
    exit 1
  fi
}

cmd_connect() {
  local ip="${1:-}"
  [ -z "$ip" ] && { echo "用法: $0 connect <IP>"; exit 1; }
  $ADB connect "$ip:5555"
  sleep 2
  $ADB devices -l
  echo "提示: 若显示 unauthorized，去电视上点【允许 USB 调试】"
}

cmd_info() {
  need_dev
  echo "型号      : $($ADB shell getprop ro.product.hisense.model | tr -d '\r')"
  echo "品牌/系统 : $($ADB shell getprop ro.product.brand | tr -d '\r') / Android $($ADB shell getprop ro.build.version.release | tr -d '\r')"
  echo "VIDAA     : $($ADB shell getprop ro.product.vidaa.version | tr -d '\r')"
  echo "固件      : $($ADB shell getprop ro.build.hisense.softversion | tr -d '\r')  构建于 $($ADB shell getprop ro.bootimage.build.date | tr -d '\r')"
  echo "ABI       : $($ADB shell getprop ro.product.cpu.abilist | tr -d '\r')"
  echo "UI 分辨率 : $($ADB shell wm size | tr -d '\r')  density $($ADB shell wm density | tr -d '\r')"
  echo "开机时长  : $($ADB shell cat /proc/uptime | tr -d '\r')"
}

cmd_mem() {
  need_dev
  $ADB shell "grep -E 'MemTotal|MemFree|MemAvailable' /proc/meminfo" | tr -d '\r'
  echo "--- PSS TOP ---"
  $ADB shell "dumpsys meminfo | sed -n '4,20p'" | tr -d '\r'
}

cmd_cpu() {
  need_dev
  $ADB shell "top -n 2 -d 2 -b -m 12 -s 9" | tr -d '\r' | tail -16
}

cmd_fps() {
  need_dev
  local pkg="${1:?用法: $0 fps <包名> [秒数]}"
  local secs="${2:-10}"
  local get_f
  get_f() { $ADB shell "dumpsys gfxinfo $pkg" 2>/dev/null | tr -d '\r' \
      | awk '/Total frames rendered/{f=$4} /Janky frames/{j=$3} END{print f, j}'; }

  local a b
  a=$(get_f); echo "起始: $a"
  echo "接下来 ${secs}s 内请用遥控器连续左右切换..."
  local n=$((secs * 2))
  for _ in $(seq 1 "$n"); do
    $ADB shell "input keyevent 22" >/dev/null 2>&1; sleep 0.25
    $ADB shell "input keyevent 21" >/dev/null 2>&1; sleep 0.25
  done
  sleep 1
  b=$(get_f); echo "结束: $b"
  echo "$a $b" | awk '{f=$3-$1; j=$4-$2; printf "新增帧=%d 卡顿=%d 掉帧率=%.1f%%\n", f, j, (f>0?j*100/f:0)}'
}

cmd_probe_codec() {
  need_dev
  echo "=== 声明能力（可能偏保守）==="
  $ADB shell "cat /vendor/etc/media_codecs.xml 2>/dev/null | grep -B2 -A4 'hevc\|avc'" | tr -d '\r' | head -40
  echo
  echo "=== 显示层真实尺寸 ==="
  $ADB shell "dumpsys SurfaceFlinger | grep -iE 'Display Root|refresh '" | tr -d '\r' | head -4
  echo
  echo "结论请以 App 内 configure(3840x2160) 是否抛异常为准，见 references/codec-and-4k.md"
}

# 实测安全可禁（不含语音，语音需自行决定）
SAFE_PKGS="
com.hisense.service.ad
com.hisense.business.ad
com.hisense.service.message
com.jamdeo.tv.fte
com.jamdeo.screensaver
com.hisense.hitv.das
com.hisense.logupload
com.hisense.autotest
com.hisense.demonstrate
com.hisense.electronictutorial
com.hisense.hotelmenu
com.hisense.systeminfo
com.hisense.nasservice
com.android.wechathci
com.hisense.familymessage
com.hisense.tv.familyalbum
com.hisense.tv.familycloud
com.jamdeo.calendar
"

cmd_clean() {
  need_dev
  echo "禁用清单（可用 pm enable 随时恢复）:"
  for p in $SAFE_PKGS; do
    printf "  %-38s -> " "$p"
    $ADB shell "pm disable-user --user 0 $p" 2>&1 | tr -d '\r'
  done
  echo
  echo "已禁用总数: $($ADB shell 'pm list packages -d | wc -l' | tr -d '\r')"
  echo "可用内存  : $($ADB shell 'grep MemAvailable /proc/meminfo' | tr -d '\r')"
}

cmd_enable() {
  need_dev
  local p="${1:?用法: $0 enable <包名>}"
  $ADB shell "pm enable $p" | tr -d '\r'
}

cmd_fix_home() {
  need_dev
  local pkg="${1:-$PKG_HOME}"
  [ -z "$pkg" ] && { echo "用法: $0 fix-home <包名>"; exit 1; }
  local svc="$pkg/$(echo "$pkg" | sed 's/\..*\.//')"
  # 约定：无障碍服务类名与包名末段相同 + HomeKeyService
  local leaf="${pkg##*.}"
  $ADB shell "settings put secure enabled_accessibility_services $pkg/$pkg.$leaf.HomeKeyService" 2>/dev/null
  # 上面的推断不一定准，兜底让用户传全名
  $ADB shell "settings put secure accessibility_enabled 1"
  $ADB shell "cmd package set-home-activity $pkg/.MainActivity"
  sleep 2
  echo "无障碍绑定: $($ADB shell 'settings get secure enabled_accessibility_services' | tr -d '\r')"
  echo "绑定计数  : $($ADB shell "dumpsys accessibility | grep -c accessibility" | tr -d '\r')"
  echo "!! 必须 reboot 才能验证开机自启"
}

cmd_shot() {
  need_dev
  local out="${1:-shot.png}"
  $ADB shell "screencap -p /sdcard/_shot.png"
  $ADB pull /sdcard/_shot.png "$out" >/dev/null 2>&1
  $ADB shell "rm -f /sdcard/_shot.png"
  echo "已保存: $out"
}

case "${1:-}" in
  connect)     shift; cmd_connect "$@" ;;
  info)        cmd_info ;;
  mem)         cmd_mem ;;
  cpu)         cmd_cpu ;;
  fps)         shift; cmd_fps "$@" ;;
  probe-codec) cmd_probe_codec ;;
  clean)       cmd_clean ;;
  enable)      shift; cmd_enable "$@" ;;
  fix-home)    shift; cmd_fix_home "$@" ;;
  shot)        shift; cmd_shot "$@" ;;
  *) sed -n '2,25p' "$0" ;;
esac
