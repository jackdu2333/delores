#!/bin/bash
#
# 划词小工具 —— 发布打包脚本
#
# 用法：
#     ./scripts/release.sh <版本号>
#
# 例：
#     ./scripts/release.sh 1.0.0
#     ./scripts/release.sh 2.0.0
#
# 产物（都在 dist/ 下，已被 .gitignore 忽略）：
#     划词小工具-<版本号>.dmg    拖拽安装盘（含 Applications 快捷方式）
#     划词小工具-<版本号>.zip    直接解压版
#
# 设计要点：
#   1. **不碰仓库根目录的 划词小工具.app** —— 那是日常运行的那一份。
#      本脚本把 .app 组装到 dist/staging/ 独立目录，构建期间不影响正在运行的应用。
#   2. **必须用固定本地证书签名**（HuaciGongju CodeSign）。
#      若退回 ad-hoc 签名，每次重新打包二进制哈希都会变，macOS 会视为陌生应用，
#      「辅助功能」授权随之失效 —— 发布包尤其不能出这种问题。
#   3. 出包后立刻做签名校验，避免把坏包发出去。
#
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "用法: $0 <版本号>   例如: $0 1.0.0"
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "版本号必须是 x.y.z 形式（例如 1.0.0），当前输入: $VERSION"
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

APP_NAME="划词小工具"
DIST="$DIR/dist"
STAGE="$DIST/staging"
OUT_APP="$STAGE/$APP_NAME.app"
SIGN_IDENTITY="HuaciGongju CodeSign"

echo "=============================================="
echo " 划词小工具 发布打包 v$VERSION"
echo "=============================================="

# --- 0. 版本号与 Info.plist 对齐检查 ---
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DIR/Resources/Info.plist")
if [ "$PLIST_VERSION" != "$VERSION" ]; then
    echo "⚠️  版本号不一致：脚本参数 $VERSION，Info.plist 是 $PLIST_VERSION"
    echo "    若确实要发布 $VERSION，请先改 Resources/Info.plist 的 CFBundleShortVersionString。"
    exit 1
fi

# --- 1. 单元测试 ---
echo ""
echo "==> 1/6 运行单元测试..."
swift run -c debug HuaciGongjuTests
echo "    ✅ 单元测试通过"

# --- 2. release 编译 ---
echo ""
echo "==> 2/6 编译 release..."
swift build -c release --product HuaciGongju
BIN_PATH="$(swift build -c release --product HuaciGongju --show-bin-path)/HuaciGongju"

# --- 3. 组装 .app（独立目录，不影响正在运行的实例）---
echo ""
echo "==> 3/6 组装 $APP_NAME.app（输出到 dist/staging，不覆盖仓库根目录实例）..."
rm -rf "$STAGE"
mkdir -p "$OUT_APP/Contents/MacOS" "$OUT_APP/Contents/Resources"
cp "$BIN_PATH" "$OUT_APP/Contents/MacOS/HuaciGongju"
chmod +x "$OUT_APP/Contents/MacOS/HuaciGongju"
cp "$DIR/Resources/Info.plist" "$OUT_APP/Contents/Info.plist"
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$OUT_APP/Contents/Resources/AppIcon.icns"
fi

# --- 4. 签名 ---
echo ""
echo "==> 4/6 签名..."
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$OUT_APP"
    echo "    已用固定本地证书签名: $SIGN_IDENTITY"
else
    echo "    ⚠️  未找到证书 $SIGN_IDENTITY，回退 ad-hoc —— 这会导致辅助功能授权每次都失效！"
    codesign --force --deep --sign - "$OUT_APP"
fi

# --- 5. 签名校验（出包前的最后一道闸）---
echo ""
echo "==> 5/6 签名校验..."
codesign --verify --deep --strict --verbose=2 "$OUT_APP" 2>&1 | sed 's/^/    /'
SIGN_INFO=$(codesign -dv "$OUT_APP" 2>&1)
echo "    $(echo "$SIGN_INFO" | grep -E '^Identifier=' | sed 's/^/    /')"
if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
    echo "    ⚠️  当前是 ad-hoc 签名，建议先安装 HuaciGongju CodeSign 证书再发布。"
fi

# --- 6. 打包 dmg + zip ---
echo ""
echo "==> 6/6 打包 dmg 与 zip..."
mkdir -p "$DIST"
# ⚠️ 归档文件名必须用 ASCII：实测 `gh release create` 上传中文名资产时，
#    非 ASCII 前缀会被静默吞掉 —— 划词小工具-1.0.0.dmg 传到 GitHub 上变成了 -1.0.0.dmg。
#    .app **内部**仍保持中文名（这是用户看到的 App 名，不能改）。
ARCHIVE_BASE="HuaciGongju-$VERSION"
DMG="$DIST/$ARCHIVE_BASE.dmg"
ZIP="$DIST/$ARCHIVE_BASE.zip"

# dmg 里放一个 /Applications 的软链，用户可直接拖进去安装
ln -sf /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" \
    | sed 's/^/    /'
rm -f "$STAGE/Applications"

# zip 用 ditto：保留资源分支与扩展属性，比普通 zip 更适合 .app bundle
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$OUT_APP" "$ZIP"

echo ""
echo "=============================================="
echo " ✅ 打包完成"
echo "=============================================="
ls -lh "$DMG" "$ZIP" | awk '{printf "    %-10s %s\n", $5, $9}'
echo ""
echo " 下一步（需你确认后执行）："
echo "   gh release create v$VERSION \\"
echo "     --title '$APP_NAME $VERSION' \\"
echo "     --generate-notes \\"
echo "     '$DMG' '$ZIP'"
