#!/bin/bash
# Build ClashCore.xcframework for iOS
# Prerequisites: 
#   - macOS with Xcode installed
#   - Go 1.22+ installed
#   - gomobile initialized: go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../core"
OUTPUT_DIR="$SCRIPT_DIR/../ios/Frameworks"

echo "🔧 Building ClashCore for iOS..."

# Check prerequisites
if ! command -v go &> /dev/null; then
    echo "❌ Error: Go is not installed"
    exit 1
fi

if ! command -v gomobile &> /dev/null; then
    echo "📦 Installing gomobile..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

cd "$CORE_DIR"

echo "📦 Building xcframework..."

# Build for iOS (arm64) and iOS Simulator (arm64, x86_64)
gomobile bind \
    -target=ios \
    -tags "with_gvisor" \
    -ldflags="-s -w" \
    -o "$OUTPUT_DIR/ClashCore.xcframework" \
    .

if [ -d "$OUTPUT_DIR/ClashCore.xcframework" ]; then
    echo "✅ ClashCore.xcframework built successfully!"
    echo "📍 Output: $OUTPUT_DIR/ClashCore.xcframework"
    ls -la "$OUTPUT_DIR"
else
    echo "❌ Build failed!"
    exit 1
fi
