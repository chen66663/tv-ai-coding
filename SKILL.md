---
name: hisense-tv-optimizer
description: 优化与接管海信（VIDAA / 聚好看）安卓电视：ADB 连接授权、卡顿与内存诊断、开机广告与预装清理、替换默认桌面、自制 Launcher APK 构建（无需 Android Studio）、4K 解码能力核实、壁纸/天气等桌面功能扩展。适用于海信电视、VIDAA 系统、Android 9 TV 的深度调优与自建桌面开发。
---

# 海信电视深度优化 / 自建桌面

这套流程来自一台 **海信 75D7H（VIDAA 6.5 / Android 9 / 3G+64G / 32 位 ABI）** 的实战，
所有命令和结论都在真机上验证过。目标不是"装几个清理软件"，而是**接管系统层**。

## 0. 开工前必读：这台机器和你想象的不一样

海信电视虽然跑 Android，但厂商做了三处硬改造，不了解就会白干：

| 改造点 | 现象 | 应对 |
|---|---|---|
| **HOME 键被框架劫持** | 设了默认桌面，按主页键仍回聚好看 | 用**无障碍服务**过滤 KEYCODE_HOME，见 `references/hisense-quirks.md` |
| **默认桌面被系统抢占** | `set-home-activity` 成功，但开机仍是聚好看 | 靠无障碍服务在 `onServiceConnected` 里延迟拉起自制桌面 |
| **32 位 ABI** | 装 64 位 APK 报 `INSTALL_FAILED_NO_MATCHING_ABIS` | 所有 APK 一律选 `armeabi-v7a` / `java32` 版本 |

## 1. 连接（最短路径）

```bash
adb connect <TV_IP>:5555      # 海信默认已开 5555，首次需在电视上点"允许"
adb devices -l                # 确认出现 device 而不是 unauthorized
```

拿 IP：电视 `设置 → 网络` 看；或用 MAC 反查
（本机 `arp -a` 里找电视无线网卡 MAC，扫描网段后可定位）。

> ⚠️ **坑 1**：`adb` daemon 在某些托管 shell 里每次调用结束就被回收。
> 由于必须"先 connect 再执行"，**把 connect 和后续命令写在同一条命令里**。
> ⚠️ **坑 2**：Git Bash 会把 `/sdcard/x.png` 转成 Windows 路径，
> `adb pull` 必须加 `MSYS_NO_PATHCONV=1`。

## 2. 诊断：先量化，再动手

**不要凭感觉说"卡"。** 至少跑这三组：

```bash
# ① 谁在吃 CPU（二次采样，避免瞬时值误导）
adb shell "top -n 2 -d 2 -b -m 10 -s 9"

# ② 包级 CPU 占比（含内核线程）
adb shell "dumpsys cpuinfo | head -25"

# ③ 界面掉帧率（关键！用前后两次读数做差，只统计"我这段时间产生的帧"）
adb shell "dumpsys gfxinfo <包名>" | grep -E "Total frames|Janky frames"
```

**坑 3：`/proc/loadavg` 在电视上是假象。** 十几的 load average 往往全部来自
TV SoC 的内核线程（`TCON_ARM_TASK`、`PQ_MPFW_TASK`、`TLV_*`、`SRC_ModeTask`）
常驻 D 状态，不代表真实负载。**别拿它下结论。**

**坑 4：`gfxinfo` 累计值会骗人。** 累计掉帧率把开机冷启动那几十帧也算进去了，
必须取两次读数之差。同一台机器累计值 52%，稳态实测可以只有 0.3%。

详细判读方法见 `references/adb-and-diagnostics.md`。

## 3. 清理：动哪些、绝不动哪些

禁用的正确姿势是 `pm disable-user --user 0 <包名>`（可逆，恢复用 `pm enable`）。

**安全的（实测无副作用）**：广告服务、消息推送、开机引导、电子说明书、
酒店菜单、自检、日志上传、行为统计、系统信息、NAS 服务、微信电视、
家庭留言板/相册/私有云、日历。

**绝对不能碰**：`com.jamdeo.tv.vod`（聚好看，引导必需）、`GlobalUI`、
`TvBaseService`、`TileTransition`（转场动画，禁了遥控器映射会失灵）。

完整清单与判断依据见 `references/package-cleanup.md`。

**开机广告**是实体文件，不在 APK 里：
`/bootad/local/misc/third_party_bootvideo.mp4`（目录 777，shell 可写），
`rm` 掉后重启验证不再回下载。属性 `ro.his.ad.adpath` 指向它。

## 4. 自建桌面 APK（不装 Android Studio）

整套工具链约 150MB，纯命令行，全流程可复现：

```
aapt(生成 R) → ecj(编译，本机无 javac 时用它) → dx(转 dex) →
aapt(打包) → zipalign → apksigner(用 openssl 生成的 key.pk8 + cert.pem 签名)
```

一键脚本：`scripts/build-apk.sh`；逐条解释与踩坑见 `references/apk-build-chain.md`。

**三个必踩的坑**：
1. `aapt package` **必须带 `-A assets`**，否则 assets 里的壁纸/配置进不了 APK
2. 焦点态缩放到 1.12x 时，**父容器会裁掉描边**，要在父链上
   `setClipChildren(false)` + `setClipToPadding(false)`
3. `ViewPropertyAnimator.withEndAction` 在开机场景可能不触发回调，
   移除浮层要用 `postDelayed` 兜底

## 5. 4K 能力核实：别猜，直接问系统

**只看 `/vendor/etc/media_codecs.xml` 会得出错误结论。**
XML 里 HEVC 常写 `max=1920x1088`，但真正 `configure(3840x2160)` 却可能被接受。

正确做法是运行时探测（本仓库 `scripts/tv.sh probe-codec`）：
- `MediaCodecInfo.getVideoCapabilities().getSupportedWidths()`
- 再真拿 3840x2160 去 `MediaCodec.configure()`，看抛不抛异常

同时用 `dumpsys SurfaceFlinger` 看 Display Root 的真实尺寸（可能是 3840x2160），
`wm size` 报的 1920x1080 只是 **UI 逻辑分辨率**（density 320 做 2 倍缩放），
**不影响视频 Overlay 层**。

详见 `references/codec-and-4k.md`。

## 6. 桌面功能扩展配方

已经做过的、可以直接抄的组件，见 `references/launcher-recipes.md`：

- 高斯模糊背景（不用 RenderScript，低分辨率 box blur 后 GPU 拉伸）
- 焦点缩放 + Overshoot 回弹
- 壁纸系统（assets 内置 + 外部目录 + 每日轮换 + 选择器网格）
- 天气（open-meteo 免费接口，城市用配置文件覆盖）
- 清后台按钮（`killBackgroundProcesses` + 旋转 + 居中结果浮层）
- 开机入场动画（逐字飞入 + 可跳过 + 强兜底移除）

## 7. 每次改完都要做的回归

```bash
adb install -r app.signed.apk
# 覆盖安装会清空无障碍绑定！必须重设
adb shell "settings put secure enabled_accessibility_services <pkg>/<pkg>.HomeKeyService"
adb shell "settings put secure accessibility_enabled 1"
adb shell "cmd package set-home-activity <pkg>/.MainActivity"
adb shell "dumpsys accessibility | grep -c '<你的服务名>'"   # 必须是 1
adb reboot                                                    # 只有重启才验证得了开机自启
```

**坑 5：`adb install -r` 会让无障碍绑定变空**，表现为"开机停在聚好看"。
这是最容易漏掉的一步。

## 参考文件

| 文件 | 内容 |
|---|---|
| `references/adb-and-diagnostics.md` | ADB 连接细节、诊断命令、指标判读 |
| `references/hisense-quirks.md` | 海信定制点（HOME 劫持、默认桌面、开机自启） |
| `references/package-cleanup.md` | 可禁/禁不得的完整包清单 |
| `references/apk-build-chain.md` | 无 IDE 构建 APK 的完整链路 |
| `references/codec-and-4k.md` | 解码能力探测与 4K 结论方法 |
| `references/launcher-recipes.md` | 自建桌面的可复用代码配方 |
| `docs/case-75d7h.md` | 一次完整实战记录（含前后数据） |
