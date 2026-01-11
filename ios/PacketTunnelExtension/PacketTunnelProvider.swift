import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let logger = Logger(subsystem: "com.ednovas.ednovas_clash_mobile.PacketTunnel", category: "tunnel")
    
    // Packet processing
    private var isRunning = false
    private var packetReadQueue: DispatchQueue?
    private var packetWriteQueue: DispatchQueue?
    
    // Track whether we're using Clash's direct TUN mode
    private var usingDirectTunMode = false
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("🚀 [PacketTunnel] startTunnel called!")
        logger.info("Starting tunnel...")
        
        guard let config = readConfigFromAppGroup() else {
            NSLog("❌ [PacketTunnel] Failed to read configuration from App Group!")
            let error = NSError(domain: "com.ednovas.clash", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read configuration"])
            completionHandler(error)
            return
        }
        
        NSLog("✅ [PacketTunnel] Config loaded, length: \(config.count) bytes")
        
        // Step 1: Set tunnel network settings FIRST (this creates the TUN interface)
        // This must happen before we try to find the TUN fd
        let settings = createTunnelSettings()
        
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                NSLog("❌ [PacketTunnel] Failed to set tunnel settings: \(error.localizedDescription)")
                self.logger.error("Failed to set tunnel settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            
            NSLog("✅ [PacketTunnel] Tunnel settings applied!")
            
            // Step 2: Find TUN file descriptor (now available after settings are applied)
            guard let tunFd = Socks5Tunnel.tunnelFileDescriptor else {
                NSLog("❌ [PacketTunnel] Could not find TUN file descriptor!")
                let error = NSError(domain: "com.ednovas.clash", code: 2, userInfo: [NSLocalizedDescriptionKey: "TUN fd not found"])
                completionHandler(error)
                return
            }
            
            NSLog("✅ [PacketTunnel] Found TUN fd: \(tunFd)")
            
            // Step 3: Start Clash Core with TUN fd - Clash handles TUN directly
            // This bypasses tun2socks entirely, avoiding all the issues with
            // hev-socks5-tunnel (crash) and Go tun2socks (localhost connection)
            let clashResult = self.startClashCoreWithFD(config: config, fd: tunFd)
            if !clashResult.isEmpty {
                NSLog("❌ [PacketTunnel] Failed to start Clash Core: \(clashResult)")
                self.logger.error("Failed to start Clash Core: \(clashResult)")
                let error = NSError(domain: "com.ednovas.clash", code: 3, userInfo: [NSLocalizedDescriptionKey: clashResult])
                completionHandler(error)
                return
            }
            
            NSLog("✅ [PacketTunnel] Clash Core started with direct TUN mode!")
            self.isRunning = true
            self.usingDirectTunMode = true
            
            self.logger.info("Tunnel started successfully with direct TUN mode")
            
            // Debug: Test if Clash API is accessible
            self.testClashAPI()
            
            completionHandler(nil)
        }
    }
    
    // MARK: - Tun2socks Integration (DEPRECATED - Using ClashStartWithFD instead)
    
    /* DEPRECATED: No longer using tun2socks - Clash Core handles TUN directly via ClashStartWithFD
    
    private func startTun2socks() -> String {
        NSLog("🔄 [PacketTunnel] startTun2socks() called")
        // ...
    }
    
    private func startGoTun2socks() -> String {
        // ...
    }
    */
    
    private func startPacketForwarding() {
        // Queue for reading packets from TUN interface
        packetReadQueue = DispatchQueue(label: "com.ednovas.clash.packetRead", qos: .userInteractive)
        // Queue for writing packets back to TUN interface
        packetWriteQueue = DispatchQueue(label: "com.ednovas.clash.packetWrite", qos: .userInteractive)
        
        // Start reading packets from TUN and sending to tun2socks
        os_log("🔄 [PacketTunnel] Starting packet forwarding loops...")
        startReadingPackets()
        
        // Start reading packets from tun2socks and writing to TUN
        startWritingPackets()
        os_log("✅ [PacketTunnel] Packet forwarding started!")
    }
    
    private var packetReadCount = 0
    private var packetWriteCount = 0
    private var lastLogTime = Date()
    
    private func startReadingPackets() {
        os_log("📖 [PacketTunnel] readPackets called, waiting for packets...")
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.isRunning else { 
                os_log("⚠️ [PacketTunnel] readPackets callback: self is nil or not running")
                return 
            }
            
            self.packetReadCount += packets.count
            
            // Log immediately for first few packets, then every 5 seconds
            if self.packetReadCount <= 5 {
                os_log("📦 [PacketTunnel] Received %d packets (total: %d)", 
                       log: OSLog.default, type: .default, 
                       packets.count, self.packetReadCount)
            } else {
                let now = Date()
                if now.timeIntervalSince(self.lastLogTime) >= 5 {
                    os_log("📊 [PacketTunnel] Stats - Read: %d packets, Write: %d packets", 
                           log: OSLog.default, type: .default, 
                           self.packetReadCount, self.packetWriteCount)
                    self.lastLogTime = now
                }
            }
            
            for (_, packet) in packets.enumerated() {
                // Send packet to tun2socks
                packet.withUnsafeBytes { rawBufferPointer in
                    guard let baseAddress = rawBufferPointer.baseAddress else { return }
                    let pointer = UnsafeMutableRawPointer(mutating: baseAddress)
                    let result = Tun2socksInputPacket(pointer.assumingMemoryBound(to: CChar.self), Int32(packet.count))
                    if result != 1 && self.packetReadCount <= 5 {
                        os_log("⚠️ [PacketTunnel] Tun2socksInputPacket returned: %d for packet size: %d", 
                               log: OSLog.default, type: .error, result, packet.count)
                    }
                }
            }
            
            // Continue reading
            if self.isRunning {
                self.startReadingPackets()
            }
        }
    }
    
    private func startWritingPackets() {
        os_log("📝 [PacketTunnel] Starting write packets loop...")
        packetWriteQueue?.async { [weak self] in
            guard let self = self else { 
                os_log("⚠️ [PacketTunnel] Write loop: self is nil")
                return 
            }
            
            os_log("📝 [PacketTunnel] Write packets loop running")
            
            // Buffer for receiving packets from tun2socks
            let bufferSize = 65535
            var buffer = [CChar](repeating: 0, count: bufferSize)
            var emptyReadCount = 0
            var loopCount = 0
            
            while self.isRunning {
                loopCount += 1
                
                // Log loop status less frequently (every 100000 to reduce overhead)
                if loopCount == 1 || loopCount % 100000 == 0 {
                    os_log("🔁 [PacketTunnel] Write loop iteration %d, empty reads: %d", 
                           log: OSLog.default, type: .default, loopCount, emptyReadCount)
                }
                
                // Try to read a packet from tun2socks
                let length = Tun2socksReadPacket(&buffer, Int32(bufferSize))
                
                if length > 0 {
                    emptyReadCount = 0  // Reset counter
                    self.packetWriteCount += 1
                    
                    // Log first few writes
                    if self.packetWriteCount <= 5 {
                        os_log("📤 [PacketTunnel] Writing packet %d, size: %d bytes", 
                               log: OSLog.default, type: .default, 
                               self.packetWriteCount, length)
                    }
                    
                    // Convert to Data
                    let packetData = Data(bytes: buffer, count: Int(length))
                    
                    // Determine protocol (IPv4 or IPv6)
                    var protocolNumber: NSNumber = 0
                    if let firstByte = packetData.first {
                        let version = (firstByte >> 4) & 0x0F
                        if version == 4 {
                            protocolNumber = NSNumber(value: AF_INET)
                        } else if version == 6 {
                            protocolNumber = NSNumber(value: AF_INET6)
                        }
                    }
                    
                    // Write packet back to TUN
                    self.packetFlow.writePackets([packetData], withProtocols: [protocolNumber])
                } else {
                    emptyReadCount += 1
                    // More aggressive adaptive delay to save CPU:
                    // - 1-10 empty reads: 1ms (responsive initial period)
                    // - 11-100 empty reads: 10ms (moderate delay)  
                    // - 101-500 empty reads: 50ms (significant delay)
                    // - 500+ empty reads: 500ms (long idle period, aggressive sleep)
                    let sleepTime: TimeInterval
                    if emptyReadCount <= 10 {
                        sleepTime = 0.001  // 1ms
                    } else if emptyReadCount <= 100 {
                        sleepTime = 0.01   // 10ms
                    } else if emptyReadCount <= 500 {
                        sleepTime = 0.05   // 50ms
                    } else {
                        sleepTime = 0.5    // 500ms for sustained idle
                    }
                    Thread.sleep(forTimeInterval: sleepTime)
                }
            }
        }
    }
    
    // MARK: - Tunnel Lifecycle
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("🛑 [PacketTunnel] stopTunnel called, reason: \(reason.rawValue)")
        logger.info("Stopping tunnel")
        isRunning = false
        
        // Only stop Clash Core - it handles TUN cleanup internally
        // Note: We're using ClashStartWithFD (direct TUN mode), not tun2socks
        let result = ClashStop()
        if let r = result {
            let resultStr = String(cString: r)
            if !resultStr.isEmpty {
                NSLog("⚠️ [PacketTunnel] ClashStop returned: \(resultStr)")
            } else {
                NSLog("✅ [PacketTunnel] Clash Core stopped successfully")
            }
        }
        
        completionHandler()
    }
    
    // MARK: - App Messages (IPC with Main App)
    
    /// Handle messages from the main app
    /// This is the ONLY way for the main app to communicate with Clash API since
    /// the main app cannot access localhost services running in the Network Extension
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let message = String(data: messageData, encoding: .utf8) else {
            NSLog("❌ [IPC] Invalid message data")
            completionHandler?(nil)
            return
        }
        
        NSLog("📨 [IPC] Received message: \(message.prefix(100))...")
        
        // First, check for legacy command format (setMode:xxx, getMode, ping)
        if message.hasPrefix("setMode:") || message == "getMode" || message == "ping" {
            handleLegacyMessage(message, completionHandler: completionHandler)
            return
        }
        
        // Parse the message format: "METHOD|||PATH|||BODY" (using ||| to avoid conflicts)
        // Example: "GET|||/proxies|||" or "PUT|||/proxies/GLOBAL|||{\"name\":\"Auto\"}"
        let parts = message.components(separatedBy: "|||")
        guard parts.count >= 2 else {
            // Legacy HTTP format support (try old : separator for backward compatibility)
            // Only if path starts with / (indicating a HTTP path)
            let legacyParts = message.components(separatedBy: ":")
            if legacyParts.count >= 2 && legacyParts[1].hasPrefix("/") {
                let method = legacyParts[0]
                let path = legacyParts[1]
                let body = legacyParts.count > 2 ? legacyParts[2...].joined(separator: ":") : ""
                forwardToClashAPI(method: method, path: path, body: body) { result in
                    completionHandler?(result)
                }
                return
            }
            // Unknown format
            NSLog("⚠️ [IPC] Unknown message format: \(message.prefix(50))...")
            completionHandler?(nil)
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        let body = parts.count > 2 ? parts[2] : ""
        
        // Forward to Clash API
        forwardToClashAPI(method: method, path: path, body: body) { result in
            completionHandler?(result)
        }
    }
    
    /// Handle legacy message format for backward compatibility
    private func handleLegacyMessage(_ message: String, completionHandler: ((Data?) -> Void)?) {
        if message.hasPrefix("setMode:") {
            let mode = String(message.dropFirst(8))
            mode.withCString { cStr in
                let mutablePtr = UnsafeMutablePointer(mutating: cStr)
                _ = ClashSetMode(mutablePtr)
            }
            completionHandler?(Data("{\"success\":true}".utf8))
        } else if message == "getMode" {
            if let result = ClashGetMode() {
                let mode = String(cString: result)
                completionHandler?(Data("{\"mode\":\"\(mode)\"}".utf8))
            } else {
                completionHandler?(Data("{\"mode\":\"rule\"}".utf8))
            }
        } else if message == "ping" {
            completionHandler?(Data("{\"status\":\"running\"}".utf8))
        } else {
            completionHandler?(nil)
        }
    }
    
    /// Forward HTTP-like request to Clash API running on localhost
    private func forwardToClashAPI(method: String, path: String, body: String, completion: @escaping (Data?) -> Void) {
        let urlString = "http://127.0.0.1:9090\(path)"
        guard let url = URL(string: urlString) else {
            NSLog("❌ [IPC] Invalid URL: \(urlString)")
            completion(Data("{\"error\":\"Invalid URL\"}".utf8))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        
        if !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("❌ [IPC] API request failed: \(error.localizedDescription)")
                completion(Data("{\"error\":\"\(error.localizedDescription)\"}".utf8))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                NSLog("✅ [IPC] API response: \(httpResponse.statusCode) for \(method) \(path)")
                
                // For 204 No Content, return success
                if httpResponse.statusCode == 204 {
                    completion(Data("{\"success\":true}".utf8))
                    return
                }
            }
            
            // Return the actual response data
            if let data = data {
                completion(data)
            } else {
                completion(Data("{\"error\":\"No data\"}".utf8))
            }
        }
        task.resume()
    }
    
    // MARK: - Helper Methods
    
    private func readConfigFromAppGroup() -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else { return nil }
        
        let configURL = containerURL.appendingPathComponent("config.yaml")
        return try? String(contentsOf: configURL, encoding: .utf8)
    }
    
    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")
        
        // IPv4 Settings - Route ALL traffic through the tunnel EXCEPT localhost
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        
        // Include default route
        ipv4.includedRoutes = [NEIPv4Route.default()]
        
        // CRITICAL: Exclude localhost (127.0.0.0/8) to prevent routing loop
        let localhostRoute = NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0")
        ipv4.excludedRoutes = [localhostRoute]
        
        settings.ipv4Settings = ipv4
        
        // NOTE: IPv6 is intentionally NOT configured here.
        // The system stack in Clash Core doesn't reliably handle IPv6 traffic.
        // All traffic will be forced to use IPv4 through the tunnel.
        
        // DNS Settings - Use public DNS servers
        // These will be routed through the TUN interface and intercepted by Clash's DNS hijack
        let dns = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
        dns.matchDomains = [""]  // Match all domains
        settings.dnsSettings = dns
        
        // MTU
        settings.mtu = 1500
        
        return settings
    }
    
    private func startClashCore(config: String) -> String {
        let homeDir = getHomeDir()
        var result: UnsafeMutablePointer<CChar>? = nil
        
        homeDir.withCString { homeDirCStr in
            config.withCString { configCStr in
                let mutableHomeDir = UnsafeMutablePointer(mutating: homeDirCStr)
                let mutableConfig = UnsafeMutablePointer(mutating: configCStr)
                result = ClashStart(mutableHomeDir, mutableConfig)
            }
        }
        
        guard let r = result else { return "" }
        return String(cString: r)
    }
    
    /// Start Clash Core with direct TUN file descriptor
    /// This allows Clash to handle TUN traffic directly, bypassing tun2socks
    private func startClashCoreWithFD(config: String, fd: Int32) -> String {
        NSLog("📦 [PacketTunnel] Starting Clash Core with TUN fd: \(fd)")
        
        let homeDir = getHomeDir()
        var result: UnsafeMutablePointer<CChar>? = nil
        
        homeDir.withCString { homeDirCStr in
            config.withCString { configCStr in
                let mutableHomeDir = UnsafeMutablePointer(mutating: homeDirCStr)
                let mutableConfig = UnsafeMutablePointer(mutating: configCStr)
                result = ClashStartWithFD(mutableHomeDir, mutableConfig, fd)
            }
        }
        
        guard let r = result else { return "" }
        let resultStr = String(cString: r)
        
        if resultStr.isEmpty {
            NSLog("✅ [PacketTunnel] ClashStartWithFD succeeded")
        } else {
            NSLog("❌ [PacketTunnel] ClashStartWithFD failed: \(resultStr)")
        }
        
        return resultStr
    }
    
    private func getHomeDir() -> String {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else { return NSTemporaryDirectory() }
        return containerURL.path
    }
    
    // MARK: - Debug
    
    private func testClashAPI() {
        guard let url = URL(string: "http://127.0.0.1:9090/version") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                NSLog("🔍 [Debug] Clash API test FAILED: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                NSLog("🔍 [Debug] Clash API test response: HTTP \(httpResponse.statusCode)")
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    NSLog("🔍 [Debug] Clash API version: \(body)")
                }
            }
        }
        task.resume()
        // Note: SOCKS port test removed - we now use direct TUN mode via ClashStartWithFD
    }
    
    private func testSOCKSPort() {
        // Test if SOCKS port (7891) is listening using a simple blocking connect
        DispatchQueue.global().async {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(7891).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            if sock < 0 {
                NSLog("🔌 [Debug] SOCKS socket creation failed: \(errno)")
                return
            }
            
            defer { close(sock) }
            
            // Set a short timeout using SO_SNDTIMEO
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            
            let connectResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if connectResult == 0 {
                NSLog("🔌 [Debug] SOCKS port 7891 - Connected ✅")
            } else {
                NSLog("🔌 [Debug] SOCKS port 7891 - Connect failed, errno: \(errno)")
            }
        }
    }
    
    /// Synchronously wait for SOCKS port to be available
    private func waitForSOCKSPort(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        let startTime = Date()
        let retryInterval: TimeInterval = 0.1
        
        while Date().timeIntervalSince(startTime) < timeout {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr(host)
            
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            if sock < 0 {
                Thread.sleep(forTimeInterval: retryInterval)
                continue
            }
            
            // Set non-blocking
            var flags = fcntl(sock, F_GETFL, 0)
            fcntl(sock, F_SETFL, flags | O_NONBLOCK)
            
            let connectResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            close(sock)
            
            if connectResult == 0 || errno == EINPROGRESS || errno == EISCONN {
                // Connection succeeded or in progress means port is listening
                return true
            }
            
            Thread.sleep(forTimeInterval: retryInterval)
        }
        
        return false
    }
}
