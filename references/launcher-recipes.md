# 自建桌面：可复用配方

一套"能上电视给人用"的桌面，核心就 6 个部件。以下都是已跑通的实现要点。

## 1. 高斯模糊背景（不依赖 RenderScript）

渲染器在某些电视 SoC 上不可用，而且每帧重算必卡。
做法：**在 160px 宽的低分辨率画布上画渐变 + 光斑，跑几遍 box blur，再交给 GPU 拉伸铺满**。
一次生成、静态复用，渲染成本≈0。

```java
// 低分辨率画布
int bw = 160, bh = 160 * h / w;
Bitmap bmp = Bitmap.createBitmap(bw, bh, ARGB_8888);
Canvas c = new Canvas(bmp);

// 底：线性渐变；再叠 3~4 个径向光斑
p.setShader(new LinearGradient(0,0,bw,bh,
        new int[]{0xFF0B1526, 0xFF16203A, 0xFF0A0D14}, null, CLAMP));
c.drawRect(0,0,bw,bh,p);
spot(c, bw*0.20f, bh*0.28f, bh*0.62f, 0x882E6BE6);   // 径向渐变光斑
...
boxBlur(bmp, 3); boxBlur(bmp, 3);                      // 两轮，等效高斯

// 绘制时直接拉伸
canvas.drawBitmap(bmp, null, new Rect(0,0,getWidth(),getHeight()), filterPaint);
// 再叠一层竖直暗化渐变，保证白字可读
```

boxBlur 就是普通的滑动窗口均值，低分辨率下几毫秒。

## 2. 焦点视觉（tvOS 风格）

规则：**缩放 1.05~1.12 + 描边 + 抬升**，不能只靠变色（远看不清）。

```java
v.setOnFocusChangeListener((view, focused) -> {
    view.animate().cancel();                       // 防抖，快速连按时必须
    view.animate().scaleX(focused ? 1.12f : 1f)
        .scaleY(focused ? 1.12f : 1f)
        .setDuration(focused ? 180 : 120)
        .setInterpolator(focused
            ? new OvershootInterpolator(1.7f)      // 进去带一点回弹
            : new DecelerateInterpolator())        // 出来干脆
        .start();
    view.setBackgroundResource(focused ? R.drawable.tile_focus : R.drawable.tile);
});
```

### ★ 描边被裁掉（必踩）

放大后超出父容器边界 → 描边只剩一部分。**在整条父链上关掉裁剪**：

```java
root.setClipChildren(false);      root.setClipToPadding(false);
layer.setClipChildren(false);     layer.setClipToPadding(false);
row.setClipChildren(false);       row.setClipToPadding(false);
```

## 3. 壁纸系统

- `assets/wallpapers/` 放内置图，`WallpaperStore.list()` 用
  `getAssets().list("wallpapers")` **动态枚举**（别写死文件名清单）
- 用户自定义：`getExternalFilesDir(null)/wallpapers`，丢 jpg/png 自动出现
- 每日轮换：SharedPreferences 存 `yyyyMMdd` + `idx`，跨天就 `idx+1`
- 解码要控内存：先 `inJustDecodeBounds` 算 `inSampleSize`，再居中裁剪到屏幕尺寸
- 选择器网格：缩略图用 `inSampleSize=8` + LruCache

## 4. 天气（open-meteo 免费接口）

```java
String u = "https://api.open-meteo.com/v1/forecast?latitude=%f&longitude=%f"
    + "&current=temperature_2m,weather_code"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,"
    + "precipitation_probability_max,wind_speed_10m_max"
    + "&timezone=Asia%2FShanghai&forecast_days=%d";
```

要点：
- **不要用 IP 定位**（走代理会定到国外）。城市写配置文件：`files/weather.txt`，一行 `城市,纬度,经度`
- **中文地名不要信 geocoding**：查"保定"会返回云南西双版纳的同名点
- 免费版 `forecast_days` **上限 16**；30 天逐日预报本身不可靠（可预报性上限 10~15 天），别造假数据
- 网络必须子线程 + 超时 + 失败保留旧值 + 30 分钟节流

## 5. 清后台按钮

```java
// manifest
<uses-permission android:name="android.permission.KILL_BACKGROUND_PROCESSES" />

// 遍历所有非系统包
for (ApplicationInfo ai : pm.getInstalledApplications(0)) {
    if (ai.packageName.equals(getPackageName())) continue;
    if ((ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
    am.killBackgroundProcesses(ai.packageName);
}
```

动效：按钮 `rotationBy(360)` 520ms；900ms 后取前后 `MemoryInfo.availMem` 差值，
居中弹一个"已清理后台 / 释放 N MB"，`Overshoot` 弹入、1.6s 后淡出。

> 效果取决于后台实况：后台干净时只显示几 MB，这是正常的。

## 6. 开场动画（逐字飞入）

```java
if (SystemClock.elapsedRealtime() > 120_000L) return;   // 只在开机 2 分钟内播

for (int i = 0; i < chars.length; i++) {
    chars[i].animate()
        .alpha(1f).translationX(0f).scaleX(1f).scaleY(1f)
        .setStartDelay(160L + i * 130L)            // 依次入场
        .setDuration(460L)
        .setInterpolator(new OvershootInterpolator(2.4f))
        .start();
}
```

字体：`Typeface.create("sans-serif-black", Typeface.BOLD_ITALIC)` + `setRotation(-5f)`
（斜体 + 一点倾角更"有劲"）。字号按屏宽取 `0.145 × 屏宽`。

### ★ 移除浮层不要依赖 withEndAction

开机场景下 `withEndAction` 实测不触发，画面会永久卡在动画最后一帧。
改为：

```java
layer.animate().cancel();
layer.animate().alpha(0f).setDuration(300).start();
mRoot.postDelayed(() -> removeIntro(layer), 340L);
mRoot.postDelayed(() -> { if (mIntroLayer != null) endIntro(); removeIntro(layer); }, 6000L); // 兜底
```

另外给一个"任意键跳过"：

```java
@Override public boolean onKeyDown(int keyCode, KeyEvent e) {
    if (mIntroLayer != null) { endIntro(); return true; }
    ...
}
```

## 7. 返回后焦点丢失

从子页面（壁纸选择器 / 天气页）返回，磁贴没有焦点也没有白框。
在 `onResume` 里补一次：

```java
if (mFirstTile != null) {
    mFirstTile.post(() -> {
        View f = getCurrentFocus();
        if (f == null || f != mFirstTile) mFirstTile.requestFocus();
    });
}
```

## 8. 磁贴数量与尺寸

- 一行放 **6 个**比较舒服；7 个会把标签挤到被裁切
- 尺寸按屏宽算：`size = (screenDp - 2*72 - n*gap) / n`，下限 104dp
- 字号跟磁贴走：`size >= 120 ? 17sp : 15sp`

## 9. 常驻入口的布局约定

参考成熟 TV 产品：

| 位置 | 放什么 |
|---|---|
| 左上 | 时钟（58sp 细体）+ 日期 |
| 时钟右侧 | 天气（可聚焦，后缀 `›` 提示可进入） |
| 右上角 | 清理 / 设置 / 返回系统（小 chip，不抢视觉） |
| 中间 | 6 个磁贴 |
| 右下角 | 壁纸 |
| 底部 | 一行操作提示（13sp，30% 白） |
