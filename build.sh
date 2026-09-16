#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# 默认执行单元测试；传 --skip-tests 可跳过（例如只需快速出包时）
RUN_TESTS=1
for arg in "$@"; do
    [ "$arg" = "--skip-tests" ] && RUN_TESTS=0
done

if [ "$RUN_TESTS" = "1" ]; then
    echo "正在运行单元测试..."
    swift run -c debug HuaciGongjuTests
    echo "✅ 单元测试通过"
fi

echo "正在编译 划词小工具 (SwiftPM release)..."
swift build -c release --product HuaciGongju

BIN_PATH="$(swift build -c release --product HuaciGongju --show-bin-path)/HuaciGongju"

APP_DIR="$DIR/划词小工具.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/HuaciGongju"
chmod +x "$APP_DIR/Contents/MacOS/HuaciGongju"

# 额外留一份裸二进制便于命令行调试（已被 .gitignore 忽略，不入库）
cp "$BIN_PATH" "$DIR/HuaciGongjuBin"

if [ -f "$DIR/Resources/Info.plist" ]; then
    cp "$DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
fi
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# 固定本地开发证书签名，避免辅助功能权限因二进制哈希变动而反复失效
SIGN_IDENTITY="HuaciGongju CodeSign"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "使用固定本地开发证书签名: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "使用临时签名 (ad-hoc)..."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "✅ 编译与签名完成！App 路径: $APP_DIR"
