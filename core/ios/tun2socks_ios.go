package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"net"
	"sync"
	"time"
	"unsafe"

	"github.com/eycorsican/go-tun2socks/core"
	"github.com/eycorsican/go-tun2socks/proxy/socks"
	"github.com/metacubex/mihomo/log"
)

var (
	tun2socksLock sync.Mutex
	lwipStack     core.LWIPStack
	isT2SRunning  bool
	outputBuffer  chan []byte
	inputCount    int64
	outputCount   int64
)

//export Tun2socksStart
func Tun2socksStart(socksHost *C.char, socksPort C.int, mtu C.int) *C.char {
	tun2socksLock.Lock()
	defer tun2socksLock.Unlock()

	if isT2SRunning {
		return C.CString("tun2socks already running")
	}

	host := C.GoString(socksHost)
	port := uint16(socksPort)
	mtuVal := int(mtu)

	log.Infoln("Starting tun2socks: SOCKS=%s:%d, MTU=%d", host, port, mtuVal)

	// Test SOCKS proxy connection first
	testAddr := fmt.Sprintf("%s:%d", host, port)
	log.Infoln("tun2socks: Testing SOCKS proxy connection to %s...", testAddr)
	
	testConn, err := net.DialTimeout("tcp", testAddr, 2*time.Second)
	if err != nil {
		log.Errorln("tun2socks: SOCKS proxy connection FAILED: %v", err)
		// Continue anyway, maybe it will work later
	} else {
		log.Infoln("tun2socks: SOCKS proxy connection SUCCESS ✅")
		testConn.Close()
	}

	// Reset counters
	inputCount = 0
	outputCount = 0

	// Create TCP and UDP handlers with correct API
	// Note: NewTCPHandler expects (proxyHost, proxyPort) not (proxyAddr, port)
	tcpHandler := socks.NewTCPHandler(host, port)
	udpHandler := socks.NewUDPHandler(host, port, 30*time.Second)

	log.Infoln("tun2socks: TCP and UDP handlers created")

	// Create the lwIP stack
	lwipStack = core.NewLWIPStack()
	log.Infoln("tun2socks: lwIP stack created")

	// Register handlers
	core.RegisterTCPConnHandler(tcpHandler)
	core.RegisterUDPConnHandler(udpHandler)
	log.Infoln("tun2socks: Handlers registered")

	// Create output buffer for packets going back to TUN
	outputBuffer = make(chan []byte, 1000)

	// Set output function (packets going to TUN)
	core.RegisterOutputFn(func(data []byte) (int, error) {
		outputCount++
		if outputCount <= 5 {
			log.Infoln("tun2socks: OutputFn called, packet #%d, size %d bytes", outputCount, len(data))
		}
		
		// Copy data since it may be reused
		packet := make([]byte, len(data))
		copy(packet, data)
		
		select {
		case outputBuffer <- packet:
		default:
			// Buffer full, drop packet
			log.Warnln("tun2socks output buffer full, dropping packet")
		}
		return len(data), nil
	})
	log.Infoln("tun2socks: Output function registered")

	isT2SRunning = true
	log.Infoln("tun2socks started successfully")
	return C.CString("")
}

//export Tun2socksInputPacket
func Tun2socksInputPacket(data *C.char, length C.int) C.int {
	if !isT2SRunning || lwipStack == nil {
		return 0
	}

	// Convert C data to Go slice
	goData := C.GoBytes(unsafe.Pointer(data), length)

	inputCount++
	if inputCount <= 5 || inputCount%1000 == 0 {
		log.Infoln("tun2socks input packet #%d, size: %d bytes", inputCount, length)
	}

	// Input the packet to lwIP stack
	_, err := lwipStack.Write(goData)
	if err != nil {
		log.Warnln("tun2socks write error: %v", err)
		return 0
	}
	return 1
}

//export Tun2socksReadPacket
func Tun2socksReadPacket(buffer *C.char, bufferSize C.int) C.int {
	if !isT2SRunning || outputBuffer == nil {
		return 0
	}

	select {
	case packet := <-outputBuffer:
		if len(packet) > int(bufferSize) {
			return 0 // Packet too large
		}
		// Copy packet to C buffer
		goBuffer := (*[1 << 30]byte)(unsafe.Pointer(buffer))[:bufferSize:bufferSize]
		copy(goBuffer, packet)
		
		outputCount++
		if outputCount <= 5 || outputCount%1000 == 0 {
			log.Infoln("tun2socks output packet #%d, size: %d bytes", outputCount, len(packet))
		}
		
		return C.int(len(packet))
	default:
		return 0 // No packet available
	}
}

//export Tun2socksStop
func Tun2socksStop() *C.char {
	tun2socksLock.Lock()
	defer tun2socksLock.Unlock()

	if !isT2SRunning {
		return C.CString("")
	}

	if lwipStack != nil {
		lwipStack.Close()
		lwipStack = nil
	}

	if outputBuffer != nil {
		close(outputBuffer)
		outputBuffer = nil
	}

	isT2SRunning = false
	log.Infoln("tun2socks stopped")
	return C.CString("")
}

//export Tun2socksIsRunning
func Tun2socksIsRunning() C.int {
	if isT2SRunning {
		return 1
	}
	return 0
}

