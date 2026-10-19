# TV AI Coding

海信（VIDAA）电视深度优化与自建桌面 —— 一套可直接复用的技能包与工具。

> 来路：一台海信 75D7H 从"运行一卡一卡"到"开机直达自制桌面、稳态掉帧 0%"的完整实战沉淀。
> 所有命令、结论、踩坑都在真机上验证过，不是从文档抄的。

## 这个仓库是什么

一个 **skill**（`SKILL.md` + `references/` + `scripts/`），用于下次优化电视时直接开干，
不用再从零试错。

```
SKILL.md                          技能主文件（工作流 + 五大坑 + 索引）
references/
  adb-and-diagnostics.md          ADB 连接细节、诊断三件套、指标误判对照表
  hisense-quirks.md               HOME 劫持 / 开机自启 / 聚好看 / 开机广告
  package-cleanup.md              可禁与禁不得的完整包清单
  apk-build-chain.md              无 Android Studio 构建 APK
  codec-and-4k.md                 解码能力探测与 4K 结论方法
  launcher-recipes.md             自建桌面的 9 个可复用配方
scripts/
  tv.sh                           调试工具集（connect/info/mem/cpu/fps/clean/fix-home）
  build-apk.sh                    一键构建签名 APK
docs/
  case-75d7h.md                   完整实战记录（含前后数据）
```

## 怎么用

### 作为 WorkBuddy / Claude 技能安装

```bash
git clone https://github.com/chen66663/tv-ai-coding.git
cp -r tv-ai-coding ~/.workbuddy/skills/hisense-tv-optimizer
```

之后提到"海信电视""VIDAA""优化电视""电视桌面"就会自动加载。

### 只当命令手册用

```bash
chmod +x scripts/tv.sh
./scripts/tv.sh connect 192.168.1.83
./scripts/tv.sh info
./scripts/tv.sh mem
./scripts/tv.sh cpu
./scripts/tv.sh fps com.jamdeo.tv.vod 10
./scripts/tv.sh clean
```

## 五个最容易踩的坑（先看这个可以省小时级时间）

1. **能力声明 ≠ 物理上限** —— `media_codecs.xml` 写 `max=1920x1088`，真拿 4K 去
   `configure()` 可能直接通过。判断 4K 必须运行时验证。
2. **`wm size` 的 1080p 不是面板分辨率** —— 那只是 UI 逻辑分辨率，视频走独立 Overlay。
3. **HOME 键被海信框架劫持** —— 设了默认桌面也没用，必须用无障碍服务过滤按键。
4. **`adb install -r` 会清空无障碍绑定** —— 表现是"开机停在聚好看"，每次装完必须重设 + 重启验证。
5. **`/proc/loadavg` 在电视上是假象** —— 十几的负载多半是 SoC 内核线程，别拿它下结论。

## 效果参考（一台 75D7H 实测）

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 稳态掉帧率 | 52.2% | **0%** |
| CPU 用户态 | 55% | 5% |
| 可用内存 | 1.19 GB | **1.47 GB** |
| 开机广告 | 有 | 无 |
| 开机落点 | 聚好看 | **自制桌面** |

## 免责

- 禁用系统组件是可逆操作（`pm enable` 可恢复），但不保证适配所有海信机型，**请先备份清单再动手**
- `scripts/tv.sh clean` 只包含实测无副作用的条目；语音引擎单独列出，需自行权衡
- 本仓库不包含任何影视源、不提供任何破解手段

## License

MIT
