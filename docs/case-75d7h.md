# 实战记录：海信 75D7H 从"一卡一卡"到自建桌面

一次完整的真机优化记录，含所有踩坑和前后数据。可作为下次作业的参照。

## 0. 设备画像

| 项 | 值 |
|---|---|
| 型号 | 海信 **75D7H**（75" 4K） |
| 系统 | **VIDAA 6.5 / Android 9 / SDK 28** |
| 固件 | `V0000.00.01U.N0423`，构建于 2023-04 |
| 板卡 | `n62020`（指纹 `NOVA72691`，解码器前缀 `OMX.NVT.*` = Novatek） |
| 内存 | MemTotal 2.53GB（标称 3G），存储 64GB |
| ABI | **只有 armeabi-v7a（32 位）** |
| 显示 | UI 逻辑 1920x1080 @320dpi；显示层 **3840x2160 @60Hz** |

## 1. 第一轮：卡顿根因

用户主诉：不是开机卡，是**运行中一卡一卡**。

### 量化

```
dumpsys cpuinfo:
  41%  com.aispeech.dui.dds.tvassistant    ← 讯飞 DUI 远场语音引擎
   9%  hstvos
   7.4% com.jamdeo.tv.vod（聚好看）
   6.6% irq/50-AUD_TOP_                     ← 音频中断
   4.4% irq/51-AUD_KRU_
```

`dumpsys gfxinfo com.jamdeo.tv.vod`：累计 6632 帧、3460 卡顿 = **52%**。

### 排除了错误方向

- `/proc/loadavg` 显示 **18**，但那是 TV SoC 内核线程常驻 D 状态的假象
- 重启（当时已 54 天没关机）**无效**，重启后语音引擎立刻又吃 40%
- `settings put global aiclientinfo '{"farswitch":"0"}'` **无效**，重启后被系统改回 1
- `am force-stop` 后**立刻被重新拉起**并再次 40%

### 处理

禁用 9 个语音相关包（引擎 + 语音 UI + 助手壳 + 语音控制）。

### 结果

| 指标 | 前 | 后 |
|---|---|---|
| CPU 空闲 | 273% | **357%** |
| 用户态 | 55% | 5% |
| 进程数 | 319 | 301 |
| 可用内存 | 1.30GB | 1.46GB |
| **稳态掉帧率** | **52.2%** | **0.3%** |

> 代价：远场语音和遥控器语音键失效。可随时 `pm enable` 恢复。

## 2. 第二轮：广告与预装

- 开机广告是**文件**：`/bootad/local/misc/third_party_bootvideo.mp4`（13.6MB），
  删掉后重启验证不再重下
- 累计禁用 **30 个**包（广告/推送/统计/日志/演示/说明书/酒店菜单/家庭系/日历/NAS/微信电视）
- 可用内存 1.19GB → **1.49GB**

## 3. 第三轮：接管桌面（最硬的一段）

### HOME 键劫持

- `cmd package set-home-activity` 返回 Success，`resolve-activity` 也解析到自制桌面
- 但按 HOME 仍回聚好看 → **框架层劫持**
- 解决：无障碍服务 `onKeyEvent` 过滤 `KEYCODE_HOME`
- 验证：`dumpsys accessibility` 显示 `capabilities=8`（可过滤按键）

### 开机直达

- `BOOT_COMPLETED` **不生效**
- 解决：在 `onServiceConnected` 里判断 `elapsedRealtime() < 120000`，延迟 2.5s 拉起
- 实测开机 15~32s 后前台即自制桌面

### 最容易漏的一步

`adb install -r` 会让 `enabled_accessibility_services` **变空**，
表现为"开机停在聚好看"。每次覆盖安装都要重设 + **重启验证**。

## 4. 第四轮：4K 判断的自我纠错

**第一次结论（错）**：XML 里 HEVC `max=1920x1088`，所以第三方 App 不可能 4K。

**推翻它的证据**：

```
getSupportedWidths() → 48-1920        ← 声明保守
configure(3840x2160) → 接受（可硬解）  ← 实际支持
dumpsys SurfaceFlinger → Display Root size=(3840,3840), refresh 16.67ms
wm size → 1920x1080                   ← 只是 UI 逻辑分辨率
```

**修正后的结论**：4K HEVC 硬解可用；`wm size` 的 1080p 与视频 Overlay 层无关。
真正的瓶颈变成网口（百兆）与片源码率。

> 教训：**能力声明 ≠ 物理上限**。必须真拿目标分辨率去 `configure()`。

## 5. 第五轮：自建桌面

### 技术栈

无 Android Studio：`aapt + ecj + dx + apksigner`，签名用 openssl 生成的 `key.pk8 + cert.pem`。
APK 从 456KB 长到 8.7MB（52 张壁纸）。

### 界面

- 高斯模糊背景（低分辨率 box blur + GPU 拉伸，不用 RenderScript）
- 6 个磁贴，焦点 1.12x + Overshoot，实测 **339 帧 0 卡顿**
- 52 张壁纸（40 实景照片 + 6 渐变 + 6 高斯模糊），选择器 5 列网格，每日轮换
- 天气（open-meteo，保定 38.8740/115.4646，可配置文件覆盖）
- 清后台按钮（实测能清掉 TVBox 49MB + 洛雪 57MB，释放 65MB）
- 开机动画"无限进步"：粗斜体 + 逐字飞入 + 可跳过

### 踩过的坑

| 坑 | 症状 | 解法 |
|---|---|---|
| 描边残缺 | 放大后白框只显示一部分 | 父链 `setClipChildren(false)` |
| `-A assets` 漏了 | 壁纸全部 FileNotFoundException | aapt 加 `-A assets` |
| `withEndAction` | 动画结束画面卡死不消失 | 改 `postDelayed` + 6 秒兜底 |
| 返回丢焦点 | 子页返回后无白框无焦点 | `onResume` 里补 `requestFocus` |
| 7 个磁贴 | 标签被裁切 | 回到 6 个，"设置"挪右上角 |
| 64 位 APK | `INSTALL_FAILED_NO_MATCHING_ABIS` | 换 `armeabi-v7a` |

## 6. 最终状态

| 指标 | 初始 | 最终 |
|---|---|---|
| 稳态掉帧率 | 52.2% | **0%** |
| CPU 用户态 | 55% | 5% |
| 可用内存 | 1.19GB | **1.47GB** |
| 禁用包 | 0 | **30** |
| 开机广告 | 有 | 无 |
| 开机落点 | 聚好看 | **自制桌面** |
| 桌面元素 | 聚好看首页（6 个内容 tab） | 时钟 + 天气 + 6 磁贴 + 壁纸 |

## 7. 没做 / 做不了的事

- 聚好看首页那排内容 tab（音乐/新闻/商城…）是**服务端下发**，无 root 删不掉；
  也不占独立进程，绕开即可
- 系统固件 `N0423` 是该机芯末版，OTA 服务器可达但永久停在"正在检查更新"
- LibreTV（Next.js 15）在 Chromium 66 的 WebView 上白屏，属内核版本硬限制
