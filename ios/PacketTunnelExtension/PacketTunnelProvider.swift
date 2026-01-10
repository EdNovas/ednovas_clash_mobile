import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let logger = Logger(subsystem: "com.ednovas.ednovas_clash_mobile.PacketTunnel", category: "tunnel")
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting tunnel...")
        
        guard let config = readConfigFromAppGroup() else {
            let error = NSError(domain: "com.ednovas.clash", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read configuration"])
            completionHandler(error)
            return
        }
        
        let result = startClashCore(config: config)
        if !result.isEmpty {
            logger.error("Failed to start Clash Core: \(result)")
            let error = NSError(domain: "com.ednovas.clash", code: 2, userInfo: [NSLocalizedDescriptionKey: result])
            completionHandler(error)
            return
        }
        
        let settings = createTunnelSettings()
        
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                self.logger.error("Failed to set tunnel settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self.logger.info("Tunnel started successfully")
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping tunnel")
        _ = ClashStop()
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let message = String(data: messageData, encoding: .utf8) {
            if message.hasPrefix("setMode:") {
                let mode = String(message.dropFirst(8))
                mode.withCString { cStr in
                    let mutablePtr = UnsafeMutablePointer(mutating: cStr)
                    _ = ClashSetMode(mutablePtr)
                }
                completionHandler?(Data("OK".utf8))
            } else if message == "getMode" {
                if let result = ClashGetMode() {
                    completionHandler?(Data(String(cString: result).utf8))
                } else {
                    completionHandler?(Data("rule".utf8))
                }
            } else {
                completionHandler?(nil)
            }
        } else {
            completionHandler?(nil)
        }
    }
    
    private func readConfigFromAppGroup() -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else { return nil }
        
        let configURL = containerURL.appendingPathComponent("config.yaml")
        return try? String(contentsOf: configURL, encoding: .utf8)
    }
    
    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: ["198.18.0.2"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
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
    
    private func getHomeDir() -> String {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else { return NSTemporaryDirectory() }
        return containerURL.path
    }
}
