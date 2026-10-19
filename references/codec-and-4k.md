# 解码能力探测与 4K 结论

## 为什么"看配置文件"会得出错误结论

`/vendor/etc/media_codecs.xml` 里常见：

```xml
<MediaCodec name="OMX.NVT.Video.Decoder.hevc" type="video/hevc">
    <Limit name="size" min="48x48" max="1920x1088" />   <!-- 写着 1080p！ -->
</MediaCodec>
```

但同一台机器上，真正拿 4K 去 `configure()` 却是**接受**的。
厂商的 capabilities 声明偏保守，实际硬解通路是开着的。

## 正确姿势：运行时三重验证

### ① 声明能力（可能保守）

```java
MediaCodecList list = new MediaCodecList(MediaCodecList.ALL_CODECS);
for (MediaCodecInfo info : list.getCodecInfos()) {
    for (String t : info.getSupportedTypes()) {
        if (t.equalsIgnoreCase("video/hevc")) {
            VideoCapabilities vc = info.getCapabilitiesForType(t).getVideoCapabilities();
            Range<Integer> w = vc.getSupportedWidths();
            Range<Integer> h = vc.getSupportedHeights();
            // info.isHardwareAccelerated() 是 API 29；API 28 用名字判断
            boolean sw = info.getName().toLowerCase().startsWith("omx.google");
        }
    }
}
```

### ② 真正 configure（关键的一步）

```java
MediaCodec c = MediaCodec.createDecoderByType("video/hevc");
MediaFormat f = MediaFormat.createVideoFormat("video/hevc", 3840, 2160);
c.configure(f, null, null, 0);   // 不抛异常 = 这条路通
c.release();
```

这一条比看 XML 可靠得多。实测某台机器：声明上限 1920，4K configure 却成功。

### ③ 显示层真实尺寸

```bash
adb shell "dumpsys SurfaceFlinger | grep -iE 'Display Root|refresh'"
```

输出里 `Display Root` 的 `size=(3840,3840)` 才是**面板真实输出尺寸**。

再看 `wm size`：

```bash
adb shell "wm size"     # Physical size: 1920x1080
```

**这两个不矛盾**：`wm size` 是 Android 的 **UI 逻辑分辨率**（density 320，即 2 倍缩放），
视频播放走独立的 **Overlay / 硬件视频层**，直接输出 4K，与 UI 层无关。
所以不能因为 `wm size=1080p` 就断言"电视不能 4K"。

## 判断流程

```
1. configure(编码格式, 3840, 2160) 通不过？
   → 该编码格式确实不能 4K，转 2
2. 通过了，但只支持 VP9 / MPEG2，不支持 HEVC？
   → 4K 片源以 HEVC 为主，实际仍不可用；YouTube 类 VP9 4K 可以
3. 通过 → 4K 可行。瓶颈转向带宽与片源码率
```

## 常见编码格式的实际差异

| 格式 | 说明 |
|---|---|
| `video/hevc`（H.265） | 4K 片源主流。**必须验这一项** |
| `video/avc`（H.264） | 4K 少见，仍值得验 |
| `video/x-vnd.on2.vp9` | YouTube 系 4K 用；很多电视只对它放开 4K |
| `video/dolby-vision` | 有解码器不代表有授权，查 `ro.his.tv.dolby_support` |

## 4K 真正的瓶颈不在解码

解码通过之后，决定"卡不卡"的是：

1. **网口**：很多电视只有百兆口。4K 原盘 40~60Mbps，加上协议开销，百兆口顶不住
2. **WiFi**：WiFi5 理论够，但 2.4G 频段实际跑不到 4K 码率，要走 5G
3. **片源本身**：同标"4K"，码率可能差 5 倍
4. **面板刷新率**：60Hz 面板播 4K/60 刚好，插帧会掉帧

测法：播放时按菜单键看帧率浮层，或

```bash
adb shell "dumpsys media.metrics | tail -40"   # 部分固件有解码统计
adb logcat -d | grep -iE "OMX|codec.*surface|dropped" | tail -20
```

## 结论话术模板

> 这台机器 `<编码格式>` 的 4K 硬解 `<支持/不支持>`，显示层输出 `<分辨率>@<刷新率>`。
> 4K 能否流畅取决于码率和网络：百兆口建议码率控制在 60Mbps 以内；WiFi 必须 5G。
