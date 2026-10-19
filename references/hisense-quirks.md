# 海信 VIDAA 定制点与会话接管

海信的 Android 是有"壳"的：`hstvos` 常驻、`GlobalUI` 负责信号源与转场、
`聚好看`（`com.jamdeo.tv.vod`）既是视频 App 又是系统 HOME。

## 1. HOME 键被框架劫持

**现象**：`cmd package set-home-activity` 返回 `Success`，`resolve-activity` 也确实解析到你的
桌面，但按主页键仍然回聚好看；从第三方应用按 HOME 也无效。

**原因**：HOME 键在框架层被接管，事件到不了 ActivityManager 的默认解析。

**解法：无障碍服务过滤按键**

```java
public class HomeKeyService extends AccessibilityService {
    @Override protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = getServiceInfo();
        info.flags |= AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS;
        setServiceInfo(info);
    }
    @Override protected boolean onKeyEvent(KeyEvent e) {
        if (e.getKeyCode() == KeyEvent.KEYCODE_HOME) {
            if (e.getAction() == KeyEvent.ACTION_UP) {
                Intent i = new Intent(this, MainActivity.class);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_SINGLE_TOP
                        | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                startActivity(i);
            }
            return true;   // 吞掉，不让海信框架处理
        }
        return false;
    }
    @Override public void onAccessibilityEvent(AccessibilityEvent e) {}
    @Override public void onInterrupt() {}
}
```

清单：

```xml
<service android:name=".HomeKeyService"
    android:exported="true"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService" />
    </intent-filter>
    <meta-data android:name="android.accessibilityservice"
        android:resource="@xml/accessibility_service_config" />
</service>
```

`res/xml/accessibility_service_config.xml`：

```xml
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagRequestFilterKeyEvents"
    android:canRequestFilterKeyEvents="true"
    android:notificationTimeout="100" />
```

**用 adb 开启**（省得用户在电视上找菜单）：

```bash
adb shell "settings put secure enabled_accessibility_services <pkg>/<pkg>.HomeKeyService"
adb shell "settings put secure accessibility_enabled 1"
adb shell "dumpsys accessibility | grep -c '<服务label>'"   # 期望 1
```

`dumpsys accessibility` 里应看到 `capabilities=8`（即 `CAN_FILTER_KEY_EVENTS`）。

> 注意：`adb shell input keyevent 3` 注入的事件**可能不经过按键过滤**，
> 所以用 adb 测不出拦截效果，**必须用实体遥控器验**。

## 2. 开机直达自制桌面

`BOOT_COMPLETED` 广播在海信上不可靠（实测不生效）。
最终方案：**在无障碍服务的 `onServiceConnected` 里判断"是不是刚开机"，延迟拉起**。

```java
@Override protected void onServiceConnected() {
    ...
    if (SystemClock.elapsedRealtime() < 120000L) {   // 开机 2 分钟内
        new Handler(getMainLooper()).postDelayed(new Runnable() {
            public void run() {
                Intent i = new Intent(HomeKeyService.this, MainActivity.class);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                try { startActivity(i); } catch (Exception ignored) {}
            }
        }, 2500L);   // 等聚好看先起来，再顶掉它
    }
}
```

配合 `cmd package set-home-activity <pkg>/.MainActivity` 一起用，成功率最高。

## 3. 覆盖安装会清空绑定（最容易漏）

`adb install -r` 之后：

```bash
adb shell "settings get secure enabled_accessibility_services"   # 变成空
```

**后果**：开机不再进自制桌面、HOME 键失效。
每次装完必须重设并**重启验证**，否则你会在用户机器上留一个"开机停在聚好看"的坑。

## 4. 聚好看（com.jamdeo.tv.vod）

- 它同时是 **HOME**、**视频 App**、**首页内容容器**。
- 首页那排 tab（音乐随心播 / 新闻 / 看电视 / 体育 / 教育 / 商城）**不是独立 APK**，
  是它内部的页面 + 服务端下发，**无 root 删不掉**；删掉它自己就等于废掉引导。
- 它常驻约 **210~230MB**。强制 `am force-stop` 能省下来，但下次点"回海信"会冷启动十几秒。
- 想彻底不要它，只能换桌面 + 接受失去海信视频入口。

## 5. 开机广告

```bash
adb shell "getprop ro.his.ad.adpath"        # /bootad/local/misc/
adb shell "ls -la /bootad/local/misc/"      # third_party_bootvideo.mp4 / *_fast_*.mp4
adb shell "rm -f /bootad/local/misc/third_party_bootvideo.mp4"
adb shell "rm -f /bootad/local/misc/third_party_fast_bootvideo.mp4"
```

目录权限 `drwxrwxrwx`，shell 用户可写。删除后重启验证没有重新下载。
广告服务包：`com.hisense.service.ad`、`com.hisense.business.ad`，一并 `pm disable-user`。

## 6. 多屏互动 / MQTT 重连

`com.hisense.tv.baseservice` 的 `JniMqttClient` 会周期性 connect/disconnect 失败重连
（实测 5 分钟 365 次）。手机遥控/投屏依赖它，禁了会一起失效，属于可选项。

## 7. 其它可读的定制属性

```bash
adb shell "getprop | grep -iE 'hisense|jamdeo|vidaa'"
```

值得注意的：
- `ro.his.tv.launcher_version`（V6LITE 等）、`ro.tv.launcher_default_theme`
- `ro.his.tv.dolby_support`（0 表示无杜比视界授权）
- `HDR_DEMON.Supported`、`ro.his.tv.sdr2hdr_supported`
- `sys.bootlog.v0..v19`（开机分段耗时）
