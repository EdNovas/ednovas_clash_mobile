//
//  Socks5Tunnel.swift
//  PacketTunnelExtension
//
//  Wrapper for hev-socks5-tunnel C library
//

import Foundation

/// Wrapper for hev-socks5-tunnel library
/// This implementation uses the C library directly, which works properly in iOS Network Extension
/// (unlike Go's net.Dial which cannot connect to localhost)
public enum Socks5Tunnel {
    
    public enum Config {
        case file(path: URL)
        case string(content: String)
    }
    
    public struct Stats {
        public struct Stat {
            public let packets: Int
            public let bytes: Int
        }
        
        public let up: Stat
        public let down: Stat
    }
    
    /// Find the TUN file descriptor by scanning open file descriptors
    /// This is the standard technique used in iOS VPN apps
    public static var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()
        withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        
        for fd: Int32 in 0...1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    ret = getpeername(fd, $0, &len)
                }
            }
            
            if ret != 0 || addr.sc_family != AF_SYSTEM {
                continue
            }
            
            if ctlInfo.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
                if ret != 0 {
                    continue
                }
            }
            
            if addr.sc_id == ctlInfo.ctl_id {
                NSLog("🔍 [Tun2Socks] Found TUN file descriptor: \(fd)")
                return fd
            }
        }
        
        NSLog("❌ [Tun2Socks] Could not find TUN file descriptor")
        return nil
    }
    
    /// Run tunnel asynchronously
    public static func run(withConfig config: Config, completionHandler: @escaping (Int32) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async {
            let code = Socks5Tunnel.run(withConfig: config)
            completionHandler(code)
        }
    }
    
    /// Run tunnel synchronously (blocks until quit is called)
    public static func run(withConfig config: Config) -> Int32 {
        guard let fileDescriptor = tunnelFileDescriptor else {
            NSLog("❌ [Tun2Socks] No TUN file descriptor available")
            return -1
        }
        
        NSLog("🚀 [Tun2Socks] Starting with fd=\(fileDescriptor)")
        
        switch config {
        case .file(let path):
            NSLog("📄 [Tun2Socks] Loading config from file: \(path.path)")
            return hev_socks5_tunnel_main(path.path.cString(using: .utf8), fileDescriptor)
        case .string(let content):
            // Use Data to get correct UTF-8 byte count (not character count)
            guard let data = content.data(using: .utf8) else {
                NSLog("❌ [Tun2Socks] Failed to encode config as UTF-8")
                return -2
            }
            
            let byteCount = UInt32(data.count)
            NSLog("📝 [Tun2Socks] Config size: \(byteCount) bytes")
            NSLog("📝 [Tun2Socks] Config content:\n\(content)")
            
            // Use withUnsafeBytes to ensure proper memory handling
            return data.withUnsafeBytes { rawBufferPointer -> Int32 in
                guard let baseAddress = rawBufferPointer.baseAddress else {
                    NSLog("❌ [Tun2Socks] Failed to get config buffer address")
                    return -3
                }
                let configPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
                let result = hev_socks5_tunnel_main_from_str(configPtr, byteCount, fileDescriptor)
                NSLog("🔍 [Tun2Socks] hev_socks5_tunnel_main_from_str returned: \(result)")
                return result
            }
        }
    }
    
    /// Get tunnel statistics
    public static var stats: Stats {
        var txPackets: Int = 0
        var txBytes: Int = 0
        var rxPackets: Int = 0
        var rxBytes: Int = 0
        hev_socks5_tunnel_stats(&txPackets, &txBytes, &rxPackets, &rxBytes)
        return Stats(
            up: Stats.Stat(packets: txPackets, bytes: txBytes),
            down: Stats.Stat(packets: rxPackets, bytes: rxBytes)
        )
    }
    
    /// Stop the tunnel
    public static func quit() {
        NSLog("🛑 [Tun2Socks] Stopping tunnel")
        hev_socks5_tunnel_quit()
    }
    
    /// Generate config for connecting to Clash SOCKS proxy
    public static func generateClashConfig(socksPort: UInt16 = 7891) -> String {
        """
        tunnel:
          mtu: 1500
        
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'udp'
        
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stderr
          log-level: info
        """
    }
}
