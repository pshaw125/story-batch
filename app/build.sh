#!/bin/bash
set -euo pipefail
APP_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$APP_ROOT/.build/native"
BUNDLE="$APP_ROOT/dist/Story Batch.app"
mkdir -p "$BUILD/module-cache" "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Frameworks" "$BUNDLE/Contents/Resources"
swiftc -swift-version 5 -O -parse-as-library -emit-module -emit-library -enable-testing \
  -module-name StoryBatchCore -module-cache-path "$BUILD/module-cache" \
  "$APP_ROOT"/Sources/StoryBatchCore/*.swift \
  -emit-module-path "$BUILD/StoryBatchCore.swiftmodule" \
  -Xlinker -install_name -Xlinker '@rpath/libStoryBatchCore.dylib' \
  -o "$BUILD/libStoryBatchCore.dylib"
swiftc -swift-version 5 -O -parse-as-library -module-cache-path "$BUILD/module-cache" \
  -I "$BUILD" -L "$BUILD" -lStoryBatchCore \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  "$APP_ROOT"/Sources/StoryBatchApp/*.swift -o "$BUNDLE/Contents/MacOS/StoryBatch"
cp "$BUILD/libStoryBatchCore.dylib" "$BUNDLE/Contents/Frameworks/"
/usr/bin/plutil -create xml1 "$BUNDLE/Contents/Info.plist"
for entry in 'CFBundleIdentifier:local.storybatch.app' 'CFBundleExecutable:StoryBatch' 'CFBundleName:Story Batch' 'CFBundlePackageType:APPL' 'CFBundleShortVersionString:1.0' 'CFBundleVersion:1' 'LSMinimumSystemVersion:13.0'; do
  /usr/bin/plutil -insert "${entry%%:*}" -string "${entry#*:}" "$BUNDLE/Contents/Info.plist"
done
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert StoryBatchWorkspace -string "$APP_ROOT" "$BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$BUNDLE/Contents/Frameworks/libStoryBatchCore.dylib"
/usr/bin/codesign --force --sign - "$BUNDLE"
echo "Built: $BUNDLE"
