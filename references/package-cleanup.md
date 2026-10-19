# 预装清理：可禁 / 禁不得

原则：**用 `pm disable-user --user 0` 而不是 `pm uninstall`**。
禁用可逆（`pm enable`），卸载系统包可能触发开机校验失败。

```bash
adb shell "pm disable-user --user 0 <包名>"
adb shell "pm enable <包名>"                 # 恢复
adb shell "pm list packages -d"               # 查看已禁用
```

## 绝对不能动（动了会卡 Logo 或按键失灵）

| 包名 | 作用 |
|---|---|
| `com.jamdeo.tv.vod` | 聚好看：系统引导 / HOME |
| `com.hisense.tv.globalui` | GlobalUI：信号源切换 |
| `com.hisense.tv.baseservice` | 系统底层服务 |
| `com.hisense.tv.tiletransition` | 转场动画；禁了遥控器映射和第三方桌面跳转会失效 |
| `com.android.systemui` / `android` / `com.android.settings` | 系统核心 |

## 实测安全可禁

### 广告与推送
```
com.hisense.service.ad            # 广告服务（含 :channel 子进程，约 60MB）
com.hisense.business.ad           # 第三条广告包
com.hisense.service.message       # 消息推送
com.jamdeo.tv.fte                 # 首次开机引导（带广告）
com.jamdeo.screensaver            # 屏保画报
```

### 统计与日志
```
com.hisense.hitv.das              # 行为统计
com.hisense.logupload             # 日志上传
com.hisense.autotest              # 自检
```

### 无用的功能壳
```
com.hisense.demonstrate           # 演示模式
com.hisense.electronictutorial    # 电子说明书
com.hisense.hotelmenu             # 酒店菜单
com.hisense.systeminfo            # SystemInfo 展示页
com.hisense.nasservice            # NAS 服务
com.android.wechathci             # 微信电视
com.hisense.familymessage         # 家庭留言板
com.hisense.tv.familyalbum        # 家庭相册
com.hisense.tv.familycloud        # 家庭私有云
com.jamdeo.calendar               # 日历
com.jamdeo.updateservice          # 系统更新（停机型机型可关）
```

### 语音（要不要关看取舍）
```
com.aispeech.dui.dds.tvassistant  # 讯飞 DUI 远场语音引擎 —— 最大的 CPU 杀手
com.keylab.speech.core.vidaa
com.keylab.speech.view.vidaa
com.hisense.vidaaassistant
com.hisense.voicecontrol
com.hisense.tv.aivirtualassistant
com.intelligent.speech
com.speech.chatroom
com.hispeech.ai.area
```

> **代价**：关掉后"小聚小聚"和遥控器语音键全部失效。
> **收益**：这台机器上实测省下 **约 0.4 个 CPU 核 + 450MB 内存**，桌面掉帧率从 52% 降到 0.5%。
> 语音引擎的问题不是"偶尔跑"，是**开机即稳定吃 37~42% 单核**，force-stop 会立刻被重新拉起，
> 改 `settings put global aiclientinfo '{"farswitch":"0"}'` 也无效（重启后被系统改回 1）。

## 谨慎（会损失实用功能）

| 包名 | 损失 |
|---|---|
| `com.hisense.wifidisplay` / `com.multiscreen.airplay` | 手机投屏 |
| `com.hisense.tv.inputs` | 信号源列表 |
| `com.sohu.inputmethod.sogou.tv` | 输入法 |
| `com.android.bluetooth` | 蓝牙遥控/耳机 |
| `com.hisense.tv.baseservice` | 手机会员遥控、多屏互动 |

## 判断方法：先看它值不值得禁

```bash
# 它占多少内存
adb shell "dumpsys meminfo | grep <包名>"
# 它是不是第三方装的（system 包才需要 disable-user，第三方直接 uninstall）
adb shell "pm list packages -3"
# 它的 APK 在哪
adb shell "pm path <包名>"
```

**经验值**：PSS < 10MB 且不是常驻服务的，禁了收益极小，别浪费时间。
值得动的门槛大约是 **20MB 或 3% CPU**。

## 清理后的验收

```bash
adb shell "pm list packages -d | wc -l"        # 禁用总数
adb shell "grep MemAvailable /proc/meminfo"    # 可用内存
adb shell "dumpsys meminfo | sed -n '4,12p'"   # 看还有谁在
```

一次实战：禁用 30 个包 + 清后台，可用内存从 **1.19GB → 1.49GB**。
