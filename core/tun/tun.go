package tun

import (
	"net"
	"net/netip"
	"strings"

	"github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// Start initializes the TUN interface.
func Start(fd int, stack string, address, dns string) (*sing_tun.Listener, error) {
	var prefix4 []netip.Prefix
	var prefix6 []netip.Prefix

	// Map stack name to constant
	tunStack := constant.TunMixed // Default to system
	if s, ok := constant.StackTypeMapping[strings.ToLower(stack)]; ok {
		tunStack = s
	}

	// Parse Addresses
	for _, a := range strings.Split(address, ",") {
		a = strings.TrimSpace(a)
		if len(a) == 0 {
			continue
		}
		prefix, err := netip.ParsePrefix(a)
		if err != nil {
			log.Errorln("TUN Address Parse Error: %s", err)
			return nil, err
		}
		if prefix.Addr().Is4() {
			prefix4 = append(prefix4, prefix)
		} else {
			prefix6 = append(prefix6, prefix)
		}
	}

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
		Stack:               tunStack,
		DNSHijack:           dnsHijack,
		AutoRoute:           false,
		AutoRedirect:        false,
		AutoDetectInterface: false,
		Inet4Address:        prefix4,
		Inet6Address:        prefix6,
		MTU:                 9000,
		FileDescriptor:      fd,
	}

	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		log.Errorln("TUN Creation Error: %s", err)
		return nil, err
	}

	return listener, nil
}
