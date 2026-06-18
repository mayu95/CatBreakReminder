#!/bin/bash
# 把 main.swift 编译成可双击运行的 CatBreak.app（菜单栏小工具），无需 Xcode。
set -e
cd "$(dirname "$0")"

APP="CatBreak.app"
EXEC="CatBreakReminder"

echo "编译中…"
swiftc -O main.swift CatArtist.swift -o "$EXEC"

echo "组装 .app …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv "$EXEC" "$APP/Contents/MacOS/$EXEC"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CatBreak</string>
    <key>CFBundleDisplayName</key><string>小猫休息提醒</string>
    <key>CFBundleIdentifier</key><string>com.catbreak.app</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>$EXEC</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>仅检测麦克风是否被占用，以判断你是否在开会，不会录音。</string>
    <key>NSCameraUsageDescription</key><string>仅检测摄像头是否被占用，以判断你是否在开会，不会拍摄。</string>
</dict>
</plist>
PLIST

# 把 assets 里的猫图打包进 Resources，并缩小到合适尺寸（显示只用 ~150px 高，原图过大白占空间）
mkdir -p "$APP/Contents/Resources"
if ls assets/*.png >/dev/null 2>&1; then
    cp assets/*.png "$APP/Contents/Resources/"
    # 缩到最高 320px（足够清晰 + 对齐扫描也按 320 处理），保留透明；源文件 assets/ 不动
    for f in "$APP/Contents/Resources/"*.png; do
        sips --resampleHeightWidthMax 320 "$f" >/dev/null 2>&1 || true
    done
    echo "已打包并压缩图片：$(ls assets/*.png | xargs -n1 basename | tr '\n' ' ')"
fi

echo "完成 → $PWD/$APP"
echo "运行：open $APP   或   ./$APP/Contents/MacOS/$EXEC（前台调试用）"
