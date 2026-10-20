#!/bin/bash
# 打包成可直接分发的 DMG：build.sh → 组装 → DMG → 校验和
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Info.plist")
OUT="$ROOT/dist"
DMG_NAME="更新雷达-${VERSION}-arm64.dmg"

echo "▸ 1/4 构建"
"$ROOT/build.sh"

echo "▸ 2/4 组装"
STAGE="$(mktemp -d)"
cp -R "$ROOT/build/更新雷达.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [ -f "$ROOT/安装说明.txt" ]; then
    cp "$ROOT/安装说明.txt" "$STAGE/"
fi

echo "▸ 3/4 生成 DMG"
mkdir -p "$OUT"
rm -f "$OUT/$DMG_NAME"
hdiutil create -volname "更新雷达 $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
    -fs HFS+ "$OUT/$DMG_NAME" >/dev/null 2>&1
rm -rf "$STAGE"

echo "▸ 4/4 校验"
ls -lh "$OUT/$DMG_NAME"
shasum -a 256 "$OUT/$DMG_NAME" | tee "$OUT/$DMG_NAME.sha256"

echo
echo "完成：$OUT/$DMG_NAME"
echo "（想放桌面：cp \"$OUT/$DMG_NAME\" ~/Desktop/）"
