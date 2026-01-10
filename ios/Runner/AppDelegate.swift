import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    private var vpnChannel: FlutterMethodChannel?
    private var vpnManager: NETunnelProviderManager?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        let controller = window?.rootViewController as! FlutterViewController
        
        // Setup VPN MethodChannel
        vpnChannel = FlutterMethodChannel(
            name: "com.ednovas.clash/vpn",
            binaryMessenger: controller.binaryMessenger
        )
        
        vpnChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleVPNMethod(call: call, result: result)
        }
        
        // Load existing VPN configuration
        loadVPNManager()
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - VPN Method Handler
    
    private func handleVPNMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startVPN(arguments: call.arguments as? [String: Any], result: result)
        case "stop":
            stopVPN(result: result)
        case "status":
            getVPNStatus(result: result)
        case "setMode":
            if let args = call.arguments as? [String: Any],
               let mode = args["mode"] as? String {
                setVPNMode(mode: mode, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing mode argument", details: nil))
            }
        case "getMode":
            getVPNMode(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - VPN Control Methods
    
    private func loadVPNManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                print("Failed to load VPN managers: \(error.localizedDescription)")
                return
            }
            
            if let manager = managers?.first {
                self?.vpnManager = manager
            } else {
                // Create new manager if none exists
                self?.createVPNManager()
            }
        }
    }
    
    private func createVPNManager() {
        let manager = NETunnelProviderManager()
        
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.ednovas.ednovas_clash_mobile.PacketTunnel"
        proto.serverAddress = "EdNovas Cloud"
        proto.providerConfiguration = [:]
        
        manager.protocolConfiguration = proto
        manager.localizedDescription = "EdNovas Clash"
        manager.isEnabled = true
        
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                print("Failed to save VPN configuration: \(error.localizedDescription)")
                return
            }
            
            manager.loadFromPreferences { error in
                if let error = error {
                    print("Failed to reload VPN configuration: \(error.localizedDescription)")
                    return
                }
                self?.vpnManager = manager
            }
        }
    }
    
    private func startVPN(arguments: [String: Any]?, result: @escaping FlutterResult) {
        guard let manager = vpnManager else {
            result(FlutterError(code: "VPN_NOT_CONFIGURED", message: "VPN manager not initialized", details: nil))
            return
        }
        
        // Save config to App Group before starting
        if let configPath = arguments?["config_path"] as? String {
            saveConfigToAppGroup(configPath: configPath)
        }
        
        do {
            try manager.connection.startVPNTunnel()
            result(nil)
        } catch {
            result(FlutterError(code: "VPN_START_FAILED", message: error.localizedDescription, details: nil))
        }
    }
    
    private func stopVPN(result: @escaping FlutterResult) {
        vpnManager?.connection.stopVPNTunnel()
        result(nil)
    }
    
    private func getVPNStatus(result: @escaping FlutterResult) {
        guard let manager = vpnManager else {
            result(false)
            return
        }
        
        let status = manager.connection.status
        result(status == .connected || status == .connecting)
    }
    
    private func setVPNMode(mode: String, result: @escaping FlutterResult) {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else {
            result(FlutterError(code: "VPN_NOT_CONNECTED", message: "VPN is not connected", details: nil))
            return
        }
        
        let message = "setMode:\(mode)"
        guard let data = message.data(using: .utf8) else {
            result(FlutterError(code: "ENCODE_ERROR", message: "Failed to encode message", details: nil))
            return
        }
        
        do {
            try session.sendProviderMessage(data) { response in
                result(nil)
            }
        } catch {
            result(FlutterError(code: "SEND_MESSAGE_FAILED", message: error.localizedDescription, details: nil))
        }
    }
    
    private func getVPNMode(result: @escaping FlutterResult) {
        // Mode is managed by Clash Core, return from shared preferences
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash") {
            let modeFile = containerURL.appendingPathComponent("current_mode.txt")
            if let mode = try? String(contentsOf: modeFile, encoding: .utf8) {
                result(mode.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
        }
        result("rule")
    }
    
    // MARK: - App Group Helpers
    
    private func saveConfigToAppGroup(configPath: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.ednovas.clash"
        ) else {
            print("Failed to get App Group container URL")
            return
        }
        
        do {
            let config = try String(contentsOfFile: configPath, encoding: .utf8)
            let destURL = containerURL.appendingPathComponent("config.yaml")
            try config.write(to: destURL, atomically: true, encoding: .utf8)
            print("Config saved to App Group")
        } catch {
            print("Failed to save config to App Group: \(error.localizedDescription)")
        }
    }
}
