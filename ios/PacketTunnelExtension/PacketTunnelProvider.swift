import NetworkExtension
import os.log
import Clashcore  // Go framework compiled by gomobile

/// EdNovas Clash PacketTunnelProvider
/// This class handles the VPN tunnel for the Clash proxy
class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let logger = Logger(subsystem: "com.ednovas.ednovas_clash_mobile.PacketTunnel", category: "tunnel")
    
    // MARK: - Tunnel Lifecycle
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting tunnel...")
        
        // 1. Read configuration from App Group shared container
        guard let config = readConfigFromAppGroup() else {
            logger.error("Failed to read config from App Group")
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read configuration"
            ]))
            return
        }
        
        // 2. Start Clash Core
        let startResult = startClashCore(config: config)
        if !startResult.isEmpty {
            logger.error("Clash Core start failed: \(startResult)")
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 2, userInfo: [
                NSLocalizedDescriptionKey: startResult
            ]))
            return
        }
        
        // 3. Configure TUN network settings
        let settings = createTunnelSettings()
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to set tunnel settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            
            self?.logger.info("Tunnel started successfully")
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping tunnel with reason: \(String(describing: reason))")
        
        stopClashCore()
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from main app (e.g., config updates, mode changes)
        guard let message = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }
        
        logger.debug("Received app message: \(message)")
        
        // Parse and handle message
        if message.hasPrefix("setMode:") {
            let mode = String(message.dropFirst("setMode:".count))
            setClashMode(mode: mode)
            completionHandler?("OK".data(using: .utf8))
        } else {
            completionHandler?(nil)
        }
    }
    
    // MARK: - Private Methods
    
    private func readConfigFromAppGroup() -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else {
            return nil
        }
        
        let configURL = containerURL.appendingPathComponent("config.yaml")
        return try? String(contentsOf: configURL, encoding: .utf8)
    }
    
    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        
        // MTU
        settings.mtu = 1500
        
        // IPv4 Settings
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = [
            // Exclude local networks
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
        ]
        settings.ipv4Settings = ipv4Settings
        
        // DNS Settings (use Clash's fake-ip DNS)
        let dnsSettings = NEDNSSettings(servers: ["198.18.0.1"])
        dnsSettings.matchDomains = [""]  // Match all domains
        settings.dnsSettings = dnsSettings
        
        return settings
    }
    
    // MARK: - Clash Core Bridge
    
    private func startClashCore(config: String) -> String {
        logger.info("Starting Clash Core with config length: \(config.count)")
        
        // Call the Go function from Clashcore.xcframework
        let result = ClashcoreStart(getHomeDir(), config)
        return result ?? ""
    }
    
    private func stopClashCore() {
        logger.info("Stopping Clash Core")
        _ = ClashcoreStop()
    }
    
    private func setClashMode(mode: String) {
        logger.info("Setting Clash mode to: \(mode)")
        _ = ClashcoreSetMode(mode)
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
