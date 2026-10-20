---
name: hisense-75d7h
description: 海信 75D7H（VIDAA 6.5 / Android 9 / 32位）这台电视的专属运维技能。用于：排查卡顿与内存、清理广告与预装、维护自制桌面（com.shcheng.home）、改壁纸/天气/开机动画、重新构建并部署 APK、恢复被禁用的系统组件。所有 IP、路径、包名、构建目录都已写死，可直接执行。
---

# 海信 75D7H 专属运维

这台机器的所有关键信息都在下面，**不用再探测一遍**。

## 设备档案（已核实）

| 项 | 值 |
|---|---|
| 型号 | 海信 **75D7H**（75" 4K，60Hz 面板） |
| 系统 | VIDAA 6.5 / **Android 9（SDK 28）** |
| 固件 | `V0000.00.01A`（构建含 N0423，2023-04；**该机芯末版，官方已停更**） |
| 板卡 | `n62020`，指纹 `NOVA72691`，解码器前缀 `OMX.NVT.*`（Novatek） |
| 内存/存储 | 2.53 GB / 64 GB |
| **ABI** | **只有 armeabi-v7a** → 装 APK 必须选 32 位（`java32` / `armeabi-v7a` / `universal`） |
| 显示 | UI 逻辑 1920×1080 @320dpi；**显示层 3840×2160 @60Hz** |
| 4K 解码 | HEVC/AVC `configure(3840×2160)` **通过**（XML 里写的 1920 是保守声明） |
| 网络 | 百兆网口 / WiFi5（4K 高码率要注意带宽） |

## 固定路径

```
电视 IP            192.168.1.83:5555   （adb 常开，首次需在电视上点允许）
本机 adb           C:/Users/qqq/platform-tools/adb.exe
自制桌面源码       C:/Users/qqq/tvbuild
一键构建           bash C:/Users/qqq/tvbuild/build.sh  → app.signed.apk
桌面包名           com.shcheng.home
桌面主页           com.shcheng.home/.MainActivity
无障碍服务         com.shcheng.home/com.shcheng.home.HomeKeyService
天气城市配置       /sdcard/Android/data/com.shcheng.home/files/weather.txt
自定义壁纸目录     /sdcard/Android/data/com.shcheng.home/files/wallpapers
调试面板           桌面按【菜单键】
```

## 日常操作：一条命令搞定

```bash
S=C:/Users/qqq/.workbuddy/skills/hisense-75d7h/scripts/tv75.sh
bash $S status      # 连上电视，看内存/前台/帧率状态
bash $S fps 10      # 测 10 秒连续切焦点的真实掉帧率
bash $S clean       # 清后台（killBackgroundProcesses）
bash $S deploy      # 重新构建 + 安装 + 重设无障碍 + 重设默认桌面
bash $S shot out.png
```

## 开机画面：直接换掉厂商的开机视频（免 root）

海信没有 `bootanimation.zip`，开机画面是 `bootad` 播放的一段**广告视频**，
放在 777 可写目录里，所以能换：

```
/bootad/local/misc/third_party_bootvideo.mp4     ← 换成自己的视频
```

**三个硬性条件**（都实测过）：
1. **必须是 MPEG-TS 封装**，扩展名仍叫 `.mp4`。放 MP4 会报 `file container not support`
2. 必须 `adb push` 到 `/sdcard/` 再用 `shell cp` 写入，直接 push 到 `/bootad` 会失败
3. 所有远端绝对路径命令要加 `MSYS_NO_PATHCONV=1`

验证：
```bash
adb logcat -d | grep -E "use bootvideo|container not support|Stop play finished"
```
看到 `use bootvideo` + `onStart` + `Stop play finished` 就是播了。
制作方法与参数见 `references/bootvideo.md`；生成脚本在 `C:/Users/qqq/tvbuild/gen_bootanim.py`。

## 三个必须记住的坑

### ⓪ 先跑一次自检（推荐开场动作）

```bash
bash C:/Users/qqq/.workbuddy/skills/hisense-75d7h/scripts/tv75.sh doctor
```

它会把**无障碍绑定、默认桌面、前台应用、内存、禁用包数**一次列全，缺什么自动补。
实测这条绑定**会自己掉**（表现为开机停在聚好看、HOME 键失效），
看到 `无障碍绑定 : （空）` 就是掉了，doctor 会自动修。

### ① 无障碍绑定是唯一的"命门"（它经常掉）
`adb install -r`、**`am force-stop com.shcheng.home`**、以及偶发的系统清理，
都会让 `enabled_accessibility_services` 变空 →
**开机停在聚好看、HOME 键失效**。每次装完/强停后必须执行：

```bash
adb shell "settings put secure enabled_accessibility_services com.shcheng.home/com.shcheng.home.HomeKeyService"
adb shell "settings put secure accessibility_enabled 1"
adb reboot   # 只有重启才验证得了开机自启
```

> **不要再执行 `cmd package set-home-activity`**：桌面已在 2026-10-20 移除了
> `CATEGORY_HOME` 声明，HOME 键 100% 由无障碍服务接管。

**自启三条腿**（海信把 `BOOT_COMPLETED` 对第三方应用屏蔽了，实测广播不送达）：
1. `BootJobService`：`JobScheduler` + `setPersisted(true)`，开机约 70 秒后自动执行，
   写回绑定并拉起桌面（**这是唯一能跨重启生效的机制**）
2. `BootReceiver`：仍然注册着，能收到就赚到
3. `HomeKeyService.onServiceConnected`：绑定没丢时立刻拉起

**lock 死桌面**：`MainActivity` 吞掉 BACK 键（`onKeyDown` return true + 空 `onBackPressed`），
离开桌面只能点右上角「海信」按钮进聚好看。子页面返回不受影响。

**已经做了自愈**：`MainActivity.selfHealAccessibility()` 在 `onResume` 检查绑定，
丢了就写回去。前提是 app 拿到 `WRITE_SECURE_SETTINGS` ——
这个权限可以 adb 授予（**必须先在 manifest 里声明**，否则报 "has not requested permission"）：

```bash
adb shell "pm grant com.shcheng.home android.permission.WRITE_SECURE_SETTINGS"
```

装完 APK 记得重跑一次这条（重装后授权会丢）。

`scripts/tv75.sh deploy` 已包含前三条，但**重启验证要你自己做**。

> **写绑定必须 toggle**：只 `settings put` 一次，`dumpsys accessibility` 里服务仍是 0（系统不去绑）。
> 必须先 `accessibility_enabled=0` → 写服务名 → `=1`。
>
> 2026-10-19 复测：即便没重装，绑定也会在某次重启后变空（`accessibility_enabled` 被置 0）。
> 原因未定位（无崩溃记录），**处理方式就是重跑 `doctor`**。
> 若反复丢失，让电视在设置→辅助功能里手动开启一次，通常能稳一段时间。

### ② 开机弹"选择主屏幕应用"怎么根治
桌面**不声明** HOME category 之后，系统启动时会去找 HOME，候选是
`聚好看` 和 `当贝桌面`，两者都没有"始终"记录 → 弹选择框，把开机流程卡住。

**根治两步**（已在这台机器上配好）：
```bash
# 1. 禁掉弃用的当贝桌面，候选只剩聚好看
adb shell "pm disable-user --user 0 com.dangbei.tvlauncher"
# 2. 把 HOME 明确指给聚好看（候选唯一时这条才会真正生效）
adb shell "cmd package set-home-activity com.jamdeo.tv.vod/com.ju.main.launcher.LauncherActivity"
```
之后：开机 → 聚好看（系统 HOME，不弹框）→ 无障碍服务 2.5s 后拉起自制桌面。

### ③ HOME 键为什么必须靠无障碍服务
`set-home-activity` 在这台机器上形同虚设；如果桌面**声明了 HOME category**，
系统会在多个候选间弹"选择主屏幕应用"，选不中就死循环，把电视卡死。
正确做法：桌面**不要声明 HOME**，只靠无障碍 `onKeyEvent` 吞掉 `KEYCODE_HOME` 再启动自己。
实测 `adb shell input keyevent 3` 能验证（会回到自制桌面）。

### ④ `wm size` 的 1080p 不是面板分辨率
那只是 UI 逻辑分辨率（density 320 两倍缩放）。视频走独立 Overlay，真 4K 输出。
判断能不能 4K，**只认 `configure(3840×2160)` 是否抛异常**。

## 卡顿排查顺序（这台机器的经验）

1. `dumpsys cpuinfo | head -30` → 看有没有进程稳定吃 30%+
2. 正常状态应该只有 `hstvos`（~9%）和聚好看（~7%）
3. 如果看到语音类进程（`aispeech` / `keylab` / `vidaaassistant`）在跑 → 它们已被禁用，
   若复活说明有人 `pm enable` 过
4. `/proc/loadavg` **别看**，这台机器常年 15+，全是 SoC 内核线程的 D 状态
5. 帧率用 `scripts/tv75.sh fps`，只认差值

## 当前状态（截至最近一次维护）

- 已禁用 **30 个**包（广告/推送/统计/日志/语音/家庭系/日历/NAS/微信电视/系统更新）
- 可用内存常态 **1.4~1.5 GB**（总 2.53 GB）
- 开机：黑底「无限进步」四字逐字飞入 → 淡出 → 自制桌面（约 1.6s，任意键跳过）
- 桌面：时钟 + 保定天气（可点进 16 天预报）+ 6 磁贴 + 52 张壁纸 + 清后台按钮
- 稳态掉帧 **0%**（连续切焦点 300+ 帧无卡顿）

详细清单见 `references/current-state.md`，改机流程见 `references/playbook.md`。

## 恢复出厂状态

```bash
bash scripts/tv75.sh restore          # 全部 pm enable
# 若要连桌面一起撤掉：
adb shell "pm uninstall com.shcheng.home"
adb shell "settings delete secure enabled_accessibility_services"
adb reboot
```

## 关联资料

完整方法论已沉淀到 GitHub：**https://github.com/chen66663/tv-ai-coding**
（含通用诊断手册、无 IDE 构建 APK、解码能力验证、桌面配方）
