package main

/*
#cgo LDFLAGS: -llog
#include <android/log.h>
#include <stdlib.h>

static inline void logToAndroid(const char* tag, const char* msg) {
	__android_log_print(ANDROID_LOG_INFO, tag, "%s", msg);
}
*/
import "C"

import (
	"ednovas/clash/core/tun"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"unsafe"

	"reflect"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	tunListener *sing_tun.Listener
	tunLock     sync.Mutex
	coreRunning bool
)

// Log to Android System Log directly
func androidLog(msg string) {
	cTag := C.CString("ClashCoreGo")
	cMsg := C.CString(msg)
	C.logToAndroid(cTag, cMsg)
	C.free(unsafe.Pointer(cTag))
	C.free(unsafe.Pointer(cMsg))
}

//export Start
func Start(homeDir *C.char, configContent *C.char, fd C.int) *C.char {
	hDir := C.GoString(homeDir)
	cfg := C.GoString(configContent)
	tunFd := int(fd)

	tunLock.Lock()
	if coreRunning {
		tunLock.Unlock()
		return C.CString("Core already running")
	}
	coreRunning = true
	tunLock.Unlock()

	constant.SetHomeDir(hDir)
	configPath := filepath.Join(hDir, "config.yaml")

	// 1. Write Config
	if err := os.WriteFile(configPath, []byte(cfg), 0644); err != nil {
		coreRunning = false
		return C.CString(fmt.Sprintf("Write Config Error: %s", err.Error()))
	}

	// 2. Parse Config & Start Hub
	if err := hub.Parse([]byte(cfg)); err != nil {
		coreRunning = false
		return C.CString(fmt.Sprintf("Hub Parse Error: %s", err.Error()))
	}

	log.Infoln("Clash Core initialized (Hub started)")

	// 3. Start TUN (if FD provided)
	// 3. Start TUN (if FD provided)
	if tunFd > 0 {
		// Hardcode values here for now to preserve existing behavior
		stack := "gvisor"
		// address := "172.19.0.1/30"
		address := "172.19.0.1/30"
		dns := "1.1.1.1,8.8.8.8"

		if errStr := StartTunWithConfig(tunFd, stack, address, dns); errStr != "" {
			// Don't kill core, just return error
			log.Errorln("TUN Start Failed: %s", errStr)
			return C.CString(fmt.Sprintf("TUN Error: %s", errStr))
		}
	}

	log.Infoln("Clash Core fully started")
	return C.CString("")
}

func takeCString(s *C.char) string {
	if s == nil {
		return ""
	}
	return C.GoString(s)
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char) bool {
	s := takeCString(stackChar)
	androidLog(fmt.Sprintf("JNI received stack: '%s', FD: %d", s, int(fd)))

	addr := takeCString(addressChar)
	d := takeCString(dnsChar)

	// DEBUG: Inspect LC.Tun struct fields directly here where we have androidLog
	t := reflect.TypeOf(LC.Tun{})
	androidLog("DEBUG: Inspecting LC.Tun struct fields:")
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		androidLog(fmt.Sprintf("Field %d: %s (Type: %s)", i, field.Name, field.Type))
	}

	errStr := StartTunWithConfig(int(fd), s, addr, d)
	if errStr != "" {
		androidLog(fmt.Sprintf("startTUN failed: %s", errStr))
		return false
	}
	return true
}

// StartTunWithConfig starts the TUN interface on the given file descriptor with provided config.
func StartTunWithConfig(fd int, stack, address, dns string) string {
	tunLock.Lock()
	defer tunLock.Unlock()

	if tunListener != nil {
		tunListener.Close()
		tunListener = nil
	}

	msg := fmt.Sprintf("Starting TUN: FD=%d, Stack=%s, Addr=%s, DNS=%s", fd, stack, address, dns)
	log.Infoln(msg)
	androidLog(msg)

	listener, err := tun.Start(fd, stack, address, dns)
	if err != nil {
		errMsg := fmt.Sprintf("Failed to create TUN listener: %v", err)
		androidLog(errMsg)
		return errMsg
	}

	tunListener = listener
	log.Infoln("TUN Listener started")
	androidLog("TUN Listener started successfully")
	return ""
}

//export Stop
func Stop() *C.char {
	tunLock.Lock()
	defer tunLock.Unlock()

	if tunListener != nil {
		tunListener.Close()
		tunListener = nil
		log.Infoln("TUN Listener closed")
	}

	// Note: Mihomo doesn't have a global "Stop" for the Hub
	coreRunning = false
	log.Infoln("Clash Core stopped")
	return C.CString("")
}

//export SetMode
func SetMode(modeChar *C.char) *C.char {
	mode := strings.ToLower(C.GoString(modeChar))

	var tunMode tunnel.TunnelMode
	switch mode {
	case "global":
		tunMode = tunnel.Global
	case "rule":
		tunMode = tunnel.Rule
	case "direct":
		tunMode = tunnel.Direct
	default:
		errMsg := fmt.Sprintf("Invalid mode: %s. Must be rule, global, or direct.", mode)
		log.Errorln(errMsg)
		return C.CString(errMsg)
	}

	tunnel.SetMode(tunMode)
	log.Infoln("Mode changed to: %s", mode)
	androidLog(fmt.Sprintf("Mode changed to: %s", mode))
	return C.CString("")
}

//export GetMode
func GetMode() *C.char {
	mode := tunnel.Mode()
	return C.CString(mode.String())
}

func main() {}
