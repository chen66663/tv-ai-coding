# 替换海信开机视频（免 root）

海信的开机画面不是 `bootanimation.zip`，而是一个**开机广告视频**，
由 `bootad` 进程播放。这个视频放在一个 **777 可写**的目录里，所以不需要 root 就能替换。

## 关键事实（全部实测）

| 项 | 值 |
|---|---|
| 视频路径 | `/bootad/local/misc/third_party_bootvideo.mp4` |
| 目录权限 | `drwxrwxrwx shell shell` —— shell（adb）可写 |
| 分区 | `/dev/block/mmcblk0p22` → `/bootad`（ext4, rw） |
| 属性 | `ro.his.ad.adpath=/bootad/local/misc/`、`persist.bootvideo.volume=9` |
| 状态属性 | `sys.bootvideo.playing`、`sys.bootvideo.type` |
| 配置播放时长 | 16.1 秒（日志 `videoPlayTime = 16103`） |
| **封装格式** | **必须是 MPEG-TS**，扩展名仍用 `.mp4` |

> 注意：这个目录本来放的是厂商的**开机广告**。删掉它广告就没了；
> 放进自己的视频，开机就播你的（同时也是最彻底的"自定义开机动画"）。

## 坑 1：MP4 不行，必须 MPEG-TS

第一次直接放 MP4，日志报：

```
initVideoPath = /bootad/local/misc/third_party_bootvideo.mp4;videoPlayTime = 16103
use bootvideo
open ts success/bootad/local/misc/third_party_bootvideo.mp4
[bootvideo] file container not support!
video format not available!! audio codec is 0 video codec is 0
```

它用 **TS demuxer** 打开（日志里 `open ts success` 就是提示）。
换成真 TS 后：

```
BootVideoAnimation::init ... Time costs: 402564 us      ← 真的在解析了
changeStatus duration: 35
BootVideoAnimation::start::start----
BootVideoAnimation:callback:onStart:
BootVideoPlayer::stopPlay() ************Stop play finished**********
```

`init` 从 3ms 变成 400ms、出现 `onStart` / `Stop play finished`，就是播上了。

## 坑 2：`adb push` 写不进去

`adb push <file> /bootad/local/misc/x.mp4` 会报 `remote secure_mkdirs failed`，
且随后 `ls` 是空的（push 服务的 mount namespace 与 shell 不同）。
**必须先 push 到 `/sdcard/`，再用 shell cp**：

```bash
adb push boot.ts /sdcard/boot.ts
adb shell "cp /sdcard/boot.ts /bootad/local/misc/third_party_bootvideo.mp4"
adb shell "chmod 644 /bootad/local/misc/third_party_bootvideo.mp4"
```

## 坑 3：Git Bash 会改写远端路径

`adb push` / `adb shell "ls /bootad/..."` 里的绝对路径会被 MSYS 转成 Windows 路径。
所有涉及远端绝对路径的命令都要加 `MSYS_NO_PATHCONV=1`。

## 制作流程

```bash
# 1. 用 Pillow 渲染帧序列（1920x1080 / 30fps / 5s = 150 帧）
#    见 tvbuild/gen_bootanim.py

# 2. 合成 MPEG-TS（带一条静音 AAC，兼容性更好）
ffmpeg -y -framerate 30 -i frames/f%04d.png \
       -f lavfi -i anullsrc=r=48000:cl=stereo \
       -c:v libx264 -profile:v main -level 4.0 -pix_fmt yuv420p -crf 18 -g 30 \
       -c:a aac -b:a 128k -shortest -f mpegts boot.ts

# 3. 校验：TS 文件头必须是 0x47
#    47 40 11 10 ...

# 4. 推送
adb push boot.ts /sdcard/boot.ts
adb shell "cp /sdcard/boot.ts /bootad/local/misc/third_party_bootvideo.mp4"
adb shell "chmod 644 /bootad/local/misc/third_party_bootvideo.mp4"

# 5. 重启看效果；验证日志
adb logcat -d | grep -E "use bootvideo|container not support|Stop play finished"
```

## 参数建议

- **分辨率** 1920x1080（面板 4K 会自动放大；直接 3840x2160 文件大一倍，收益不明显）
- **帧率** 30fps 足够，`-g 30` 关键帧对齐
- **时长** 4~6 秒。配置的 16.1 秒是上限，播完会自动切走；
  做得太短会"一闪而过"，5 秒左右比较从容
- **音频** 加一条静音 AAC，避免某些固件因无音轨判为格式异常
- **首帧** 建议纯黑，与开机黑屏衔接自然

## 字体倾斜：用旋转，别用仿射斜切

做"斜体"时如果用 `Image.transform` 做 shear，字形右上角会被裁掉一块
（输出画布宽度算不准，且超出部分直接丢失）。
正确做法是 **`img.rotate(-8, expand=True)`** —— 整字旋转 8°，
`expand=True` 会自动扩大画布，**保证笔画一个都不丢**。

App 内同理：`TextView.setRotation(-8f)`，比 `paint.setTextSkewX()` 安全
（skew 只影响绘制、不影响测量，右侧会被 TextView 自身宽度裁掉）。

## 回滚

```bash
adb shell "rm -f /bootad/local/misc/third_party_bootvideo.mp4"
adb reboot
# 没有该文件时 bootad 会退回默认动画（也就是回到"无广告"状态）
```
