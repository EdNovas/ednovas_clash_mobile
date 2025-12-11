#!/bin/bash
set -e

# ==========================================
# Clash Core Android AAR Build Script
# For Ubuntu 24.04 (AMD64)
# ==========================================

WORKDIR="$HOME/clash_build"
ANDROID_ROOT="$HOME/android_sdk"
GO_ROOT="/usr/local/go"
OUTPUT_DIR="$PWD/output"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$ANDROID_ROOT"

echo "=== 1. Installing System Dependencies ==="
sudo apt-get update
sudo apt-get install -y curl git unzip tar build-essential openjdk-17-jdk

echo "=== 2. Setup Go Environment ==="
if ! command -v go &> /dev/null; then
    echo "Downloading Go 1.22..."
    curl -L https://go.dev/dl/go1.22.1.linux-amd64.tar.gz -o go.tar.gz
    sudo rm -rf "$GO_ROOT"
    sudo tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
fi
export PATH=$PATH:$GO_ROOT/bin:$(go env GOPATH)/bin
echo "Go Version: $(go version)"

echo "=== 3. Setup Android SDK & NDK ==="
export ANDROID_HOME="$ANDROID_ROOT"
export NDK_VERSION="26.1.10909125"

if [ ! -d "$ANDROID_HOME/cmdline-tools" ]; then
    echo "Downloading Android Command Line Tools..."
    curl -L https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o cmdline-tools.zip
    unzip -q cmdline-tools.zip -d "$ANDROID_HOME"
    # Reorganize for sdkmanager requirements
    mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
    mv "$ANDROID_HOME/cmdline-tools/bin" "$ANDROID_HOME/cmdline-tools/latest/"
    mv "$ANDROID_HOME/cmdline-tools/lib" "$ANDROID_HOME/cmdline-tools/latest/"
    mv "$ANDROID_HOME/cmdline-tools/NOTICE.txt" "$ANDROID_HOME/cmdline-tools/latest/"
    mv "$ANDROID_HOME/cmdline-tools/source.properties" "$ANDROID_HOME/cmdline-tools/latest/"
    rm cmdline-tools.zip
fi

export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

echo "Accepting Licenses..."
yes | sdkmanager --licenses > /dev/null

echo "Installing Android Build Tools & NDK..."
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" "ndk;$NDK_VERSION"

export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"

echo "=== 4. Prepare Clash Source Code ==="
cd "$WORKDIR"

# Initialize Go Module
if [ ! -f "go.mod" ]; then
    go mod init clash
    # Replace with mihomo (Clash.Meta)
    go get github.com/metacubex/mihomo@v1.18.0
    go get golang.org/x/mobile/bind
fi

# Create Wrapper Code (lib.go) matches Java: clash.Clash
# Package name must be 'clash' to generate 'clash.Clash' class
cat > lib.go <<EOF
package clash

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
    // Import empty feature packages to ensure they are compiled in
    _ "github.com/metacubex/mihomo/features/dns"
    _ "github.com/metacubex/mihomo/features/outbound"
)

// Start initializes and starts the Clash core.
func Start(homeDir string, configContent string) string {
	constant.SetHomeDir(homeDir)

	configPath := filepath.Join(homeDir, "config.yaml")
	// Attempt to write config, but don't fail hard if permissions issue, 
    // assuming Start might be called with path in future or content is enough.
    // For now, write it for standard compatibility.
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		return fmt.Sprintf("Write Config Failed: %s", err.Error())
	}

	cfg, err := config.ParseAndBuild(configPath)
	if err != nil {
		return fmt.Sprintf("Config Parse Failed: %s", err.Error())
	}

	if err := hub.Parse(cfg); err != nil {
		return fmt.Sprintf("Hub Start Failed: %s", err.Error())
	}
	
	return "Clash Core Started V6 (Mihomo)"
}

// Stop stops the Clash core (Stub)
func Stop() string {
    return "Stopped" 
}
EOF

# Ensure dependencies
go mod tidy

echo "=== 5. Setup Gomobile ==="
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

echo "=== 6. Build AAR ==="
echo "Building libclash.aar for Android..."
# Generate AAR
# -target=android implies arm64-v8a, armeabi-v7a, x86, x86_64
echo "Compiling with tags: with_gvisor (Critical for Android VPN)"
gomobile bind -target=android -o libclash.aar -ldflags="-s -w" -tags "with_gvisor" .

echo "=== Build Complete ==="
cp libclash.aar "$OUTPUT_DIR/"
echo "Success! The file is located at: $OUTPUT_DIR/libclash.aar"
