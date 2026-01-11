#!/bin/bash

# iOS Clashcore.xcframework 构建脚本
# 在 Mac 上运行此脚本来编译 iOS 核心库

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios"
OUTPUT_DIR="$SCRIPT_DIR/../ios"

echo "================================================"
echo "EdNovas Clash iOS Core 构建脚本"
echo "================================================"

# 检查 Go 环境
if ! command -v go &> /dev/null; then
    echo "❌ Go 未安装。请先安装 Go:"
    echo "   brew install go"
    exit 1
fi

GO_VERSION=$(go version)
echo "✅ Go: $GO_VERSION"

# 检查是否在 macOS 上
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 此脚本必须在 macOS 上运行"
    exit 1
fi

echo "✅ 运行在 macOS 上"

# 检查 Xcode 命令行工具
if ! command -v xcrun &> /dev/null; then
    echo "❌ Xcode 命令行工具未安装"
    echo "   请运行: xcode-select --install"
    exit 1
fi

echo "✅ Xcode: $(xcodebuild -version | head -1)"

# 设置 iOS SDK
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
IOS_SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
IOS_CC=$(xcrun --sdk iphoneos --find clang)
IOS_SIM_CC=$(xcrun --sdk iphonesimulator --find clang)

echo "✅ iOS SDK: $IOS_SDK"
echo "✅ iOS Simulator SDK: $IOS_SIM_SDK"

# 创建输出目录
BUILD_DIR="$SCRIPT_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$IOS_DIR"

# 安装依赖
echo ""
echo "📦 安装 Go 依赖..."
go mod download

# ======================
# 构建 iOS arm64 (真机)
# ======================
echo ""
echo "🔨 构建 iOS arm64 (真机)..."
CGO_ENABLED=1 \
GOOS=ios \
GOARCH=arm64 \
CC="$IOS_CC" \
CGO_CFLAGS="-isysroot $IOS_SDK -arch arm64 -miphoneos-version-min=15.0" \
CGO_LDFLAGS="-isysroot $IOS_SDK -arch arm64 -miphoneos-version-min=15.0" \
go build -tags with_gvisor -buildmode=c-archive -o "$BUILD_DIR/libclashcore_ios_arm64.a" .

echo "✅ iOS arm64 构建完成"

# =========================================
# 构建 iOS Simulator arm64 (Apple Silicon)
# =========================================
echo ""
echo "🔨 构建 iOS Simulator arm64 (Apple Silicon Mac)..."
CGO_ENABLED=1 \
GOOS=ios \
GOARCH=arm64 \
CC="$IOS_SIM_CC" \
CGO_CFLAGS="-isysroot $IOS_SIM_SDK -arch arm64 -miphonesimulator-version-min=15.0 -target arm64-apple-ios15.0-simulator" \
CGO_LDFLAGS="-isysroot $IOS_SIM_SDK -arch arm64 -miphonesimulator-version-min=15.0 -target arm64-apple-ios15.0-simulator" \
go build -tags with_gvisor -buildmode=c-archive -o "$BUILD_DIR/libclashcore_sim_arm64.a" .

echo "✅ iOS Simulator arm64 构建完成"

# ======================
# 创建 xcframework
# ======================
echo ""
echo "📦 创建 xcframework..."

# 复制头文件
mkdir -p "$BUILD_DIR/ios-headers"
mkdir -p "$BUILD_DIR/sim-headers"
cp "$BUILD_DIR/libclashcore_ios_arm64.h" "$BUILD_DIR/ios-headers/libclashcore.h"
cp "$BUILD_DIR/libclashcore_sim_arm64.h" "$BUILD_DIR/sim-headers/libclashcore.h"

# 删除旧的 xcframework
rm -rf "$OUTPUT_DIR/Clashcore.xcframework"

# 创建 xcframework
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/libclashcore_ios_arm64.a" \
    -headers "$BUILD_DIR/ios-headers" \
    -library "$BUILD_DIR/libclashcore_sim_arm64.a" \
    -headers "$BUILD_DIR/sim-headers" \
    -output "$OUTPUT_DIR/Clashcore.xcframework"

echo ""
echo "================================================"
echo "✅ 构建成功！"
echo ""
echo "输出位置: $OUTPUT_DIR/Clashcore.xcframework"
echo ""
echo "包含的架构:"
echo "  - iOS arm64 (真机)"
echo "  - iOS Simulator arm64 (Apple Silicon Mac)"
echo ""
echo "新增 API:"
echo "  - ClashStartWithFD(homeDir, config, fd) - 支持文件描述符"
echo "================================================"

# 清理
echo ""
echo "🧹 清理临时文件..."
rm -rf "$BUILD_DIR"

echo ""
echo "🎉 完成！现在可以在 Xcode 中构建 iOS 应用了。"
