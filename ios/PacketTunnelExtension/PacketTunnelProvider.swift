import NetworkExtension
import os.log

/// EdNovas Clash PacketTunnelProvider
/// This class handles the VPN tunnel for the Clash proxy
class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let logger = Logger(subsystem: "com.ednovas.ednovas_clash_mobile.PacketTunnel", category: "tunnel")
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting tunnel...")
        
        // Read configuration from App Group
        guard let config = readConfigFromAppGroup() else {
            let error = NSError(domain: "com.ednovas.clash", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read configuration"])
            completionHandler(error)
            return
        }
        
        // Start Clash Core
        let result = startClashCore(config: config)
        if !result.isEmpty {
            logger.error("Failed to start Clash Core: \(result)")
            let error = NSError(domain: "com.ednovas.clash", code: 2, userInfo: [NSLocalizedDescriptionKey: result])
            completionHandler(error)
            return
        }
        
        // Configure network settings
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
        logger.info("Stopping tunnel with reason: \(String(describing: reason))")
        
        stopClashCore()
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app
        if let message = String(data: messageData, encoding: .utf8) {
            logger.info("Received message: \(message)")
            
            if message.hasPrefix("setMode:") {
                let mode = String(message.dropFirst(8))
                setClashMode(mode: mode)
                completionHandler?(Data("OK".utf8))
            } else if message == "getMode" {
                let mode = getClashMode()
                completionHandler?(Data(mode.utf8))
            } else {
                completionHandler?(nil)
            }
        } else {
            completionHandler?(nil)
        }
    }
    
    // MARK: - Configuration
    
    private func readConfigFromAppGroup() -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else {
            logger.error("Failed to get App Group container URL")
            return nil
        }
        
        let configURL = containerURL.appendingPathComponent("config.yaml")
        
        do {
            let config = try String(contentsOf: configURL, encoding: .utf8)
            logger.info("Config loaded, length: \(config.count)")
            return config
        } catch {
            logger.error("Failed to read config: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")
        
        // IPv4 configuration
        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings
        
        // DNS configuration
        let dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings
        
        return settings
    }
    
    // MARK: - Clash Core Bridge (C Functions from libclashcore)
    
    private func startClashCore(config: String) -> String {
        logger.info("Starting Clash Core with config length: \(config.count)")
        
        // Call the C function from the static library
        let homeDir = getHomeDir()
        guard let result = ClashStart(
            (homeDir as NSString).utf8String,
            (config as NSString).utf8String
        ) else {
            return ""
        }
        return String(cString: result)
    }
    
    private func stopClashCore() {
        logger.info("Stopping Clash Core")
        _ = ClashStop()
    }
    
    private func setClashMode(mode: String) {
        logger.info("Setting Clash mode to: \(mode)")
        _ = ClashSetMode((mode as NSString).utf8String)
    }
    
    private func getClashMode() -> String {
        guard let result = ClashGetMode() else {
            return "rule"
        }
        return String(cString: result)
    }
    
    private func getHomeDir() -> String {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else {
            return NSTemporaryDirectory()
        }
        return containerURL.path
    }
}
