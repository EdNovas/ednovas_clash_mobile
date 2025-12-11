package main

import "C"

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
    // Import features to ensure compilation
    _ "github.com/metacubex/mihomo/features/dns"
    _ "github.com/metacubex/mihomo/features/outbound"
)

var (
	params *hub.Option
)

//export Start
func Start(homeDir *C.char, configContent *C.char) *C.char {
    goHomeDir := C.GoString(homeDir)
    goConfigContent := C.GoString(configContent)

	// 1. Set Home Directory
	constant.SetHomeDir(goHomeDir)

	// 2. Write Config
	configPath := filepath.Join(goHomeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(goConfigContent), 0644); err != nil {
		return C.CString(fmt.Sprintf("Error writing config: %s", err.Error()))
	}

	// 3. Parse Config
	cfg, err := config.ParseAndBuild(configPath)
	if err != nil {
		return C.CString(fmt.Sprintf("Config Error: %s", err.Error()))
	}

	// 4. Start Hub
	if err := hub.Parse(cfg); err != nil {
		return C.CString(fmt.Sprintf("Hub Error: %s", err.Error()))
	}
	
	return C.CString("Clash Core Started (Mihomo/Native)")
}

//export Stop
func Stop() *C.char {
	return C.CString("Stopped")
}

func main() {} // Required for c-shared build
