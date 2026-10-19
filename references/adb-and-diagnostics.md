# ADB 连接与诊断手册

## 连接

海信电视出厂一般已开启 `adb tcpip 5555`。首次连接电视上会弹"允许 USB 调试吗"，
点允许并勾选"一律允许"。

```bash
adb connect 192.168.1.83:5555
adb devices -l        # 期望：192.168.1.83:5555  device
```

**找不到 IP 时**：从 MAC 反查。

```bash
# 电视 设置→网络→本机信息 里有 有线/无线 MAC
arp -a | grep -i "bc-5c-17"          # Linux/macOS 风格
# Windows：arp -a 后按 MAC 前两段找
# 若 ARP 表里没有，先扫一遍网段
for i in $(seq 1 254); do ping -n 1 -w 200 192.168.1.$i >/dev/null 2>&1 & done; wait
arp -a | grep "192.168.1."
```

### 两个环境坑

**① daemon 被回收**
某些托管终端（如 WorkBuddy 的 bash 工具）每次调用结束会把 `adb` daemon 一并结束，
下一条命令就变成 `no devices/emulators found`。解决办法：**把 connect 和业务命令写在同一条**。

```bash
adb connect $IP:5555 >/dev/null 2>&1; sleep 2; adb shell "getprop ro.product.model"
```

**② 路径被 Git Bash 转换**
`adb pull /sdcard/a.png out.png` 会把 `/sdcard/a.png` 当成绝对路径改写。
必须：

```bash
MSYS_NO_PATHCONV=1 adb pull /sdcard/a.png out.png
```

## 基础信息采集

```bash
adb shell "getprop ro.product.hisense.model"     # 真实型号，如 75D7H
adb shell "getprop ro.build.version.release"     # Android 版本
adb shell "getprop ro.product.vidaa.version"     # VIDAA 版本，如 6.5
adb shell "getprop ro.build.hisense.softversion" # 固件，如 V0000.00.01U
adb shell "getprop ro.bootimage.build.date"      # 固件构建日期
adb shell "wm size; wm density"                  # UI 逻辑分辨率
adb shell "cat /proc/uptime"                     # 开机时长，判断是否长期没重启
```

## 诊断三件套

### 1. CPU：谁在跑

```bash
# 二次采样（-n 2 输出两帧，取第二帧才准）
adb shell "top -n 2 -d 2 -b -m 12 -s 9"

# 包级占比，含内核线程
adb shell "dumpsys cpuinfo | head -30"
```

判读要点：
- `%CPU` 是**相对单核**的。400%cpu 表示 4 核；某进程 40% = 吃掉 0.4 核
- 持续 30~40% 的单核占用，在 4 核电视上足以让 UI 抖动
- 音频类 `irq/*-AUD_*` 高，通常是某个常驻语音/麦克风服务在反复开关

### 2. 内存：谁占着

```bash
adb shell "grep -E 'MemTotal|MemAvailable|Cached' /proc/meminfo"
adb shell "dumpsys meminfo | sed -n '4,25p'"     # Total PSS by process
```

- 关注 **MemAvailable**（不是 MemFree，Free 低是正常的缓存占用）
- 电视 2.5GB 总内存，可用低于 800MB 就开始有压力
- `dumpsys meminfo` 里 PSS 200MB+ 的基本都是桌面/视频类应用

### 3. 流畅度：掉帧率

```bash
# 单次快照（含累计值，仅供定位）
adb shell "dumpsys gfxinfo <包名>"

# 正确做法：前后做差
get_f() { adb shell "dumpsys gfxinfo <包名>" | awk '/Total frames rendered/{f=$4} /Janky frames/{j=$3} END{print f, j}'; }
A=$(get_f); <执行一段操作>; B=$(get_f)
echo "$A $B" | awk '{f=$3-$1; j=$4-$2; printf "新增帧=%d 卡顿=%d 掉帧率=%.1f%%\n", f,j,(f>0?j*100/f:0)}'
```

判读：
- **< 2%**：体感顺滑
- **5~20%**：能感觉到掉帧
- **> 30%**：明显卡顿

其它有用字段：`50th/90th/99th percentile`（单帧耗时分布）、
`Number Slow issue draw commands`（绘制太重）、`Missed Vsync`（错过垂直同步）。

### 4. 开机耗时（分段）

海信会往 `sys.bootlog.v0..v19` 写各阶段耗时，单位看起来是微秒：

```bash
adb shell "getprop | grep sys.bootlog"
```

## 常见误判

| 指标 | 陷阱 | 正确理解 |
|---|---|---|
| `/proc/loadavg` | 电视上常年 10~20 | 几乎全是 SoC 内核线程的 D 状态，不是真负载 |
| `MemFree` 很低 | 以为内存不足 | Linux 会拿空闲内存做缓存，看 MemAvailable |
| `gfxinfo` 累计掉帧率 | 把开机冷启动算进去 | 必须做差，看稳态 |
| `wm size` = 1920x1080 | 以为电视不能 4K | 这只是 UI 逻辑分辨率，视频走独立 Overlay |
| `top` 单次采样 | 抓到的可能是瞬时峰值 | 至少 `-n 2 -d 2` |

## 抓日志

```bash
adb logcat -d -v time > tv.log      # 全量
adb logcat -d -b crash             # 只看崩溃
grep -icE "skipped [0-9]+ frames|ANR in|Slow Looper" tv.log
```

某些海信固件的 logcat 里**看不到普通应用的 Log.i**（被裁剪），
排查时改用**写文件 + adb pull** 更可靠：

```java
new FileOutputStream(new File(getExternalFilesDir(null), "probe.txt")).write(...)
```
