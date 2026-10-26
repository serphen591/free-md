#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"
ditto build/免费版md.app "$STAGE/免费版md.app"
ln -s /Applications "$STAGE/Applications"
cp 安装与使用说明.txt "$STAGE/安装与使用说明.txt"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
xcrun SetFile -a C "$STAGE" 2>/dev/null || true
mkdir -p release
hdiutil create -volname '免费版md' -srcfolder "$STAGE" -ov -fs HFS+ -format UDZO -imagekey zlib-level=9 'release/FreeMD-1.0.1-universal.dmg'
hdiutil verify 'release/FreeMD-1.0.1-universal.dmg'
(cd release && shasum -a 256 'FreeMD-1.0.1-universal.dmg' > 'SHA256SUMS.txt')
cp 安装与使用说明.txt release/
