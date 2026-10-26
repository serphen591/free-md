#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build release
npm run build
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -target "$arch-apple-macosx12.0" -O Sources/Core.swift Sources/Preview.swift Sources/Archive.swift Sources/App.swift Sources/main.swift -o "build/FreeMD-$arch"
done
APP="build/免费版md.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/FreeMD-arm64 build/FreeMD-x86_64 -output "$APP/Contents/MacOS/FreeMD"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/AppIcon.png Resources/preview.html Resources/preview.css Resources/ThirdPartyLicenses.txt "$APP/Contents/Resources/"
rsync -a --delete Resources/vendor/ "$APP/Contents/Resources/vendor/"
codesign --force --sign - --identifier app.freemd.local "$APP"
codesign --verify --deep --strict "$APP"
