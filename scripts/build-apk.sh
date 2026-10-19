#!/usr/bin/env bash
# 无 Android Studio 构建 APK 的模板脚本
#
# 目录约定:
#   ./AndroidManifest.xml
#   ./src/**.java
#   ./res/
#   ./assets/            (可无)
#   ./tools/bt/           build-tools 解压目录（内含 aapt.exe / lib/dx.jar ...）
#   ./tools/platform/android.jar
#   ./tools/ecj.jar      (本机无 javac 时)
#   ./key.pk8 ./cert.pem (签名材料，首次运行会自动生成)
#
# 用法: ./build-apk.sh [输出名.apk]

set -e
cd "$(dirname "$0")"

OUT="${1:-app.signed.apk}"
BT="${BT:-tools/bt}"
AJ="${AJ:-tools/platform/android.jar}"
JAVA="${JAVA:-java}"
AAPT="$BT/aapt.exe"; [ -x "$AAPT" ] || AAPT="$BT/aapt"
ZIPALIGN="$BT/zipalign.exe"; [ -x "$ZIPALIGN" ] || ZIPALIGN="$BT/zipalign"

[ -f "$AJ" ] || { echo "缺少 $AJ"; exit 1; }

rm -rf gen obj
mkdir -p gen obj

echo "[1/7] 生成 R.java"
"$AAPT" package -f -m -J gen -M AndroidManifest.xml -S res -I "$AJ"

echo "[2/7] 编译 Java"
if command -v javac >/dev/null 2>&1; then
  javac -source 8 -target 8 -encoding UTF-8 -bootclasspath "$AJ" -d obj \
        $(find src gen -name "*.java") 2>/dev/null || \
  javac -encoding UTF-8 -classpath "$AJ" -d obj $(find src gen -name "*.java")
else
  [ -f tools/ecj.jar ] || { echo "无 javac 且缺少 tools/ecj.jar"; exit 1; }
  "$JAVA" -jar tools/ecj.jar -source 1.8 -target 1.8 -encoding UTF-8 \
          -bootclasspath "$AJ" -d obj $(find src gen -name "*.java")
fi

echo "[3/7] 生成 dex"
if [ -f "$BT/lib/dx.jar" ]; then
  "$JAVA" -Xmx1024M -jar "$BT/lib/dx.jar" --dex --output=classes.dex obj
else
  # build-tools 30+ 用 d8
  "$JAVA" -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 \
          --lib "$AJ" --output . obj 2>/dev/null || \
  { mkdir -p dexout && "$JAVA" -cp "$BT/lib/d8.jar" com.android.tools.r8.D8 \
      --lib "$AJ" --output dexout obj && mv dexout/classes.dex .; }
fi

echo "[4/7] 打包"
ASSETS_OPT=""
[ -d assets ] && ASSETS_OPT="-A assets"     # ★ 忘了它会丢 assets
"$AAPT" package -f -M AndroidManifest.xml -S res $ASSETS_OPT -I "$AJ" -F app.unsigned.apk
"$AAPT" add app.unsigned.apk classes.dex >/dev/null

echo "[5/7] 对齐"
"$ZIPALIGN" -f -p 4 app.unsigned.apk app.aligned.apk

echo "[6/7] 签名"
if [ ! -f key.pk8 ] || [ ! -f cert.pem ]; then
  echo "  生成自签名密钥..."
  openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem \
          -days 10000 -subj "/CN=MyTVApp" 2>/dev/null
  openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out key.pk8 -nocrypt
fi
"$JAVA" -jar "$BT/lib/apksigner.jar" sign \
        --key key.pk8 --cert cert.pem \
        --v1-signing-enabled true --v2-signing-enabled true \
        --out "$OUT" app.aligned.apk

echo "[7/7] 完成"
ls -la "$OUT"
echo
echo "安装: adb install -r $OUT"
echo "!! 覆盖安装会清空无障碍绑定，装完必须执行 scripts/tv.sh fix-home <包名> 并重启验证"
