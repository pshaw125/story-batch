#!/bin/bash
set -euo pipefail
APP_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$APP_ROOT/.build/tests"
mkdir -p "$BUILD/module-cache"
swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -enable-testing \
  -module-name StoryBatchCore -module-cache-path "$BUILD/module-cache" \
  "$APP_ROOT"/Sources/StoryBatchCore/*.swift \
  -emit-module-path "$BUILD/StoryBatchCore.swiftmodule" \
  -Xlinker -install_name -Xlinker '@rpath/libStoryBatchCore.dylib' \
  -o "$BUILD/libStoryBatchCore.dylib"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD/module-cache" \
  -I "$BUILD" -L "$BUILD" -lStoryBatchCore -Xlinker -rpath -Xlinker "$BUILD" \
  "$APP_ROOT"/Tests/StoryBatchCoreTests/*.swift "$APP_ROOT/scripts/StandaloneTests.swift" \
  -o "$BUILD/StoryBatchTests"
"$BUILD/StoryBatchTests"
swiftc -swift-version 5 -parse-as-library -D STORYBATCH_MODEL_TESTS \
  -module-cache-path "$BUILD/module-cache" -I "$BUILD" -L "$BUILD" -lStoryBatchCore \
  -Xlinker -rpath -Xlinker "$BUILD" \
  "$APP_ROOT"/Sources/StoryBatchApp/*.swift \
  "$APP_ROOT"/Tests/StoryBatchCoreTests/*.swift \
  "$APP_ROOT/scripts/StandaloneTests.swift" "$APP_ROOT/scripts/AppModelTests.swift" \
  -o "$BUILD/AppModelTests"
"$BUILD/AppModelTests"
