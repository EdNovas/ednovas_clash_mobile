#!/bin/bash
set -e

# ================= 配置区域 =================
# 与您之前的配置保持一致
NDK_VERSION="r26b"
GO_VERSION="1.22.5"
WORK_DIR="$(pwd)/flclash_build_env"
REPO_URL="https://github.com/chen08209/FlClash.git"
OUTPUT_DIR="$(pwd)/android_libs"
# ===========================================

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> [1/7] 初始化环境...${NC}"
sudo apt-get update && sudo apt-get install -y wget unzip git build-essential curl

mkdir -p "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$WORK_DIR"

echo -e "${GREEN}>>> [2/7] 检查/安装 Go $GO_VERSION...${NC}"
if ! command -v go &> /dev/null; then
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O go.tar.gz
    rm -rf go && tar -xzf go.tar.gz
    export PATH="$WORK_DIR/go/bin:$PATH"
else
    echo "Go 已安装"
fi

echo -e "${GREEN}>>> [3/7] 检查/安装 NDK $NDK_VERSION...${NC}"
if [ ! -d "android-ndk-$NDK_VERSION" ]; then
    wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" -O ndk.zip
    unzip -q ndk.zip && rm ndk.zip
else
    echo "NDK 已安装"
fi
export ANDROID_NDK="$WORK_DIR/android-ndk-$NDK_VERSION"

echo -e "${GREEN}>>> [4/7] 拉取源码...${NC}"
if [ ! -d "FlClash" ]; then
    git clone --depth=1 "$REPO_URL" FlClash
    cd FlClash
else
    cd FlClash
fi

echo -e "${YELLOW}>>> 修复 .gitmodules URL...${NC}"
if [ -f ".gitmodules" ]; then
    sed -i 's/git@github.com:/https:\/\/github.com\//g' .gitmodules
    git submodule sync
fi

echo "正在更新子模块..."
git submodule update --init --recursive

# 切换到 core 目录
cd core

# =================================================================
# 【关键步骤】: 覆盖 lib.go
# FlClash 原生的 lib.go 导出的函数跟我们要用的不一样 (startTUN vs Start)。
# 我们必须注入适配我们 App 的接口。
# =================================================================
# =================================================================
# 【关键修复】: 注入 JNA 兼容的 lib.go
# 原版 FlClash 使用 JNI 对象作为 callback，JNA 无法使用。
# 我们在这里重写 lib.go，改为接受 C 函数指针 (CallbackFunc)。
# =================================================================
echo -e "${YELLOW}>>> 清理冲突文件 (hub.go, action.go 等)...${NC}"
rm -f *.go

echo -e "${YELLOW}>>> 正在注入 JNA 适配版 lib.go...${NC}"
cat > lib.go <<EOF
package main

/*
#include <stdlib.h>

typedef void (*CallbackFunc)(char*);

static void call_callback(void* f, char* str) {
    if (f) {
        ((CallbackFunc)f)(str);
    }
}
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
    "unsafe"


	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
)

var (
    GlobalHomeDir string
)

type ActionRequest struct {
    Id     string      \`json:"id"\`
    Method string      \`json:"method"\`
    Data   interface{} \`json:"data"\`
}

type ActionResponse struct {
    Id     string      \`json:"id"\`
    Method string      \`json:"method"\`
    Data   interface{} \`json:"data"\`
    Code   int         \`json:"code"\`
}

//export invokeAction
func invokeAction(callback unsafe.Pointer, paramsChar *C.char) {
    jsonStr := C.GoString(paramsChar)
    
    var req ActionRequest
    json.Unmarshal([]byte(jsonStr), &req)
    
    var respData interface{}
    
    switch req.Method {
    case "initClash":
        homeDir, ok := req.Data.(string)
        if ok {
            respData = jnaHandleInit(homeDir)
        } else {
            respData = "Invalid data type for initClash"
        }
    case "updateConfig":
        configContent, ok := req.Data.(string)
        if ok {
            respData = jnaHandleUpdateConfig(configContent)
        }
    default:
        respData = "Unknown method"
    }

    resp := ActionResponse{
        Id: req.Id,
        Method: req.Method,
        Data: respData,
        Code: 0,
    }
    respBytes, _ := json.Marshal(resp)
    
    cStr := C.CString(string(respBytes))
    defer C.free(unsafe.Pointer(cStr))
    
    C.call_callback(callback, cStr)
}

func jnaHandleInit(homeDir string) string {
    GlobalHomeDir = homeDir
    constant.SetHomeDir(homeDir)
    return "Initialized"
}

func jnaHandleUpdateConfig(content string) string {
    path := filepath.Join(GlobalHomeDir, "config.yaml")
    os.WriteFile(path, []byte(content), 0644)
    
    // Based on compiler error, hub.Parse accepts []byte
    if err := hub.Parse([]byte(content)); err != nil {
        return fmt.Sprintf("Hub Error: %s", err.Error())
    }
    return "Config Updated & Hub Started"
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char) bool {
    return true
}

//export stopTun
func stopTun() {
}

func main() {}
EOF

echo -e "${YELLOW}>>> 更新依赖...${NC}"
go mod tidy
# =================================================================

# ================= 编译循环 =================
build_arch() {
    local ABI_NAME=$1   
    local GO_ARCH=$2    
    local CC_BIN=$3     
    local GO_ARM=$4     

    echo -e "${GREEN}>>> [编译中] $ABI_NAME (GoArch: $GO_ARCH)...${NC}"

    local CC_PATH="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/$CC_BIN"
    
    if [ ! -f "$CC_PATH" ]; then
        echo "错误: 找不到编译器 $CC_PATH"
        return 1
    fi

    local TARGET_DIR="$OUTPUT_DIR/$ABI_NAME"
    mkdir -p "$TARGET_DIR"

    export CGO_ENABLED=1
    export GOOS=android
    export GOARCH=$GO_ARCH
    export CC="$CC_PATH"
    export CFLAGS="-O3 -Werror"
    if [ -n "$GO_ARM" ]; then export GOARM=$GO_ARM; fi

    # Go Build (启用 with_gvisor)
    go build -v -ldflags="-s -w" -tags=with_gvisor -buildmode=c-shared -o "$TARGET_DIR/libclash.so"

    unset GOARM
    echo -e "${GREEN}>>> [完成] $ABI_NAME -> $TARGET_DIR/libclash.so${NC}"
}

# 开始编译
build_arch "arm64-v8a" "arm64" "aarch64-linux-android21-clang"
build_arch "armeabi-v7a" "arm" "armv7a-linux-androideabi21-clang" "7"
build_arch "x86_64" "amd64" "x86_64-linux-android21-clang"

echo -e "${GREEN}>>> [7/7] 全部完成！请将 $OUTPUT_DIR 下的文件覆盖到项目中。${NC}"
