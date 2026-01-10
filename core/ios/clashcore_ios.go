package main

/*
#include <stdlib.h>
*/
import "C"
import (
    "fmt"
    "os"
    "path/filepath"
    "strings"
    "sync"

    "github.com/metacubex/mihomo/constant"
    "github.com/metacubex/mihomo/hub"
    "github.com/metacubex/mihomo/tunnel"
)

var (
    coreLock    sync.Mutex
    coreRunning bool
)

//export ClashStart
func ClashStart(homeDir, configContent *C.char) *C.char {
    coreLock.Lock()
    if coreRunning {
        coreLock.Unlock()
        return C.CString("Core already running")
    }
    coreRunning = true
    coreLock.Unlock()

    homeDirGo := C.GoString(homeDir)
    configGo := C.GoString(configContent)
    
    constant.SetHomeDir(homeDirGo)
    configPath := filepath.Join(homeDirGo, "config.yaml")

    if err := os.WriteFile(configPath, []byte(configGo), 0644); err != nil {
        coreRunning = false
        return C.CString(fmt.Sprintf("Write Config Error: %s", err.Error()))
    }

    if err := hub.Parse([]byte(configGo)); err != nil {
        coreRunning = false
        return C.CString(fmt.Sprintf("Hub Parse Error: %s", err.Error()))
    }

    return C.CString("")
}

//export ClashStop
func ClashStop() *C.char {
    coreLock.Lock()
    defer coreLock.Unlock()
    if !coreRunning {
        return C.CString("")
    }
    coreRunning = false
    return C.CString("")
}

//export ClashSetMode
func ClashSetMode(mode *C.char) *C.char {
    modeGo := strings.ToLower(C.GoString(mode))
    switch modeGo {
    case "rule", "global", "direct":
        tunnel.SetMode(tunnel.ModeMapping[modeGo])
        return C.CString("")
    default:
        return C.CString("Invalid mode")
    }
}

//export ClashGetMode
func ClashGetMode() *C.char {
    return C.CString(strings.ToLower(tunnel.Mode().String()))
}

//export ClashIsRunning
func ClashIsRunning() C.int {
    if coreRunning {
        return 1
    }
    return 0
}

//export ClashGetVersion
func ClashGetVersion() *C.char {
    return C.CString("ClashCore/iOS-1.0")
}

func main() {}
