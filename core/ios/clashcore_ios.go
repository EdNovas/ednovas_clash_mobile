package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	coreLock    sync.Mutex
	coreRunning bool
	tunListener *sing_tun.Listener
	tunLock     sync.Mutex
)

//export ClashStart
func ClashStart(homeDir, configContent *C.char) *C.char {
	return ClashStartWithFD(homeDir, configContent, -1)
}

//export ClashStartWithFD
func ClashStartWithFD(homeDir, configContent *C.char, fd C.int) *C.char {
	coreLock.Lock()
	if coreRunning {
		coreLock.Unlock()
		return C.CString("Core already running")
	}
	coreRunning = true
	coreLock.Unlock()

	homeDirGo := C.GoString(homeDir)
	configGo := C.GoString(configContent)
	tunFd := int(fd)

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

	log.Infoln("Clash Core initialized (Hub started)")

	// Start TUN if FD provided
	if tunFd > 0 {
		if err := startTunWithFD(tunFd); err != "" {
			log.Errorln("TUN Start Failed: %s", err)
			return C.CString(fmt.Sprintf("TUN Error: %s", err))
		}
		log.Infoln("TUN Listener started successfully")
	}

	log.Infoln("Clash Core fully started")
	return C.CString("")
}

func startTunWithFD(fd int) string {
	tunLock.Lock()
	defer tunLock.Unlock()

	if tunListener != nil {
		tunListener.Close()
		tunListener = nil
	}

	// Use gVisor stack - this creates a userspace TCP/IP stack that properly
	// handles raw IP packets from iOS NEPacketTunnelProvider TUN fd.
	// The system stack doesn't work in iOS sandbox environment.
	// Requires: go build -tags with_gvisor
	stack := constant.TunGvisor
	address := "198.18.0.1/16"
	dns := "8.8.8.8,1.1.1.1"

	log.Infoln("Starting TUN: FD=%d, Stack=%s, Addr=%s, DNS=%s", fd, "system", address, dns)

	// Parse IPv4 Address
	var prefix4 []netip.Prefix
	p4, err := netip.ParsePrefix(address)
	if err != nil {
		return fmt.Sprintf("Failed to parse address: %v", err)
	}
	prefix4 = append(prefix4, p4)

	// Parse DNS Hijack
	var dnsHijack []string
	for _, d := range strings.Split(dns, ",") {
		d = strings.TrimSpace(d)
		if len(d) > 0 {
			dnsHijack = append(dnsHijack, net.JoinHostPort(d, "53"))
		}
	}

	options := LC.Tun{
		Enable:              true,
		Device:              "",
		Stack:               stack,
		DNSHijack:           dnsHijack,
		AutoRoute:           false,
		AutoRedirect:        false,
		AutoDetectInterface: false,
		Inet4Address:        prefix4,
		MTU:                 1500, // Must match iOS tunnel MTU setting
		FileDescriptor:      fd,
	}

	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		return fmt.Sprintf("Failed to create TUN listener: %v", err)
	}

	tunListener = listener
	return ""
}

//export ClashStop
func ClashStop() *C.char {
	coreLock.Lock()
	defer coreLock.Unlock()

	tunLock.Lock()
	if tunListener != nil {
		tunListener.Close()
		tunListener = nil
		log.Infoln("TUN Listener closed")
	}
	tunLock.Unlock()

	if !coreRunning {
		return C.CString("")
	}
	coreRunning = false
	log.Infoln("Clash Core stopped")
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
	return C.CString("ClashCore/iOS-1.2")
}

func main() {}
