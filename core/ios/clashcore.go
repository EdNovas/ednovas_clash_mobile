// Package clashcore provides Go bindings for iOS
// This package is designed for gomobile bind
package clashcore

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	coreLock    sync.Mutex
	coreRunning bool
)

// Start initializes and starts the Clash core with the given configuration
// homeDir: directory for Clash data files
// configContent: YAML configuration content
// Returns empty string on success, error message on failure
func Start(homeDir, configContent string) string {
	coreLock.Lock()
	if coreRunning {
		coreLock.Unlock()
		return "Core already running"
	}
	coreRunning = true
	coreLock.Unlock()

	constant.SetHomeDir(homeDir)
	configPath := filepath.Join(homeDir, "config.yaml")

	// Write Config
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		coreRunning = false
		return fmt.Sprintf("Write Config Error: %s", err.Error())
	}

	// Parse Config & Start Hub
	if err := hub.Parse([]byte(configContent)); err != nil {
		coreRunning = false
		return fmt.Sprintf("Hub Parse Error: %s", err.Error())
	}

	log.Infoln("Clash Core initialized")
	return ""
}

// Stop shuts down the Clash core
// Returns empty string on success
func Stop() string {
	coreLock.Lock()
	defer coreLock.Unlock()

	coreRunning = false
	log.Infoln("Clash Core stopped")
	return ""
}

// SetMode changes the proxy mode (rule, global, direct)
// Returns empty string on success, error message on failure
func SetMode(mode string) string {
	mode = strings.ToLower(mode)

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
		return errMsg
	}

	tunnel.SetMode(tunMode)
	log.Infoln("Mode changed to: %s", mode)
	return ""
}

// GetMode returns the current proxy mode
func GetMode() string {
	mode := tunnel.Mode()
	return mode.String()
}

// IsRunning returns whether the core is currently running
func IsRunning() bool {
	coreLock.Lock()
	defer coreLock.Unlock()
	return coreRunning
}

// GetVersion returns the core version info
func GetVersion() string {
	return "ClashCore/iOS-1.0"
}
