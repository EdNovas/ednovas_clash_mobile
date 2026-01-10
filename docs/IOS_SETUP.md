# iOS Support for EdNovas Clash Mobile

## Overview

This directory contains the iOS implementation for EdNovas Clash Mobile VPN client.

## Architecture

```
ios/
├── Runner/                         # Main Flutter app
│   ├── AppDelegate.swift          # VPN MethodChannel bridge
│   └── Runner.entitlements        # App permissions
├── PacketTunnelExtension/         # NetworkExtension for VPN
│   ├── PacketTunnelProvider.swift # Tunnel implementation
│   ├── Info.plist                 # Extension configuration
│   └── *.entitlements             # Extension permissions
└── Frameworks/                     # Compiled Go core (after build)
    └── ClashCore.xcframework
```

## Prerequisites

1. **macOS** with Xcode 15+ installed
2. **Apple Developer Account** ($99/year)
3. **Go 1.22+** and **gomobile** installed

## Setup Steps

### 1. Build Go Core for iOS

```bash
# On macOS only
cd scripts
chmod +x build_ios_core.sh
./build_ios_core.sh
```

### 2. Configure Xcode Project

Open `ios/Runner.xcworkspace` in Xcode and:

1. **Add PacketTunnelExtension target**:
   - File → New → Target → Network Extension → Packet Tunnel Provider

2. **Configure Signing**:
   - Select your Team for both Runner and PacketTunnelExtension
   - Enable "Automatically manage signing"

3. **Add Entitlements**:
   - Runner target: Enable Network Extensions and App Groups
   - PacketTunnelExtension: Same as above

4. **Add ClashCore.xcframework**:
   - Drag `ios/Frameworks/ClashCore.xcframework` into both targets
   - Ensure "Embed & Sign" is selected

### 3. Configure App Groups

In Apple Developer Portal:
1. Create App Group: `group.com.ednovas.clash`
2. Add to both App IDs (main app and extension)
3. Regenerate provisioning profiles

## Testing

VPN functionality requires a **physical iOS device** - it cannot be tested on Simulator.

```bash
# Build for device
flutter build ios --release

# Or run on connected device
flutter run -d <device_id>
```

## Deployment

### TestFlight

1. Archive: Product → Archive
2. Upload to App Store Connect
3. Add testers in TestFlight section

### App Store

Note: VPN apps require additional review. Include:
- Privacy policy URL
- VPN functionality description
- Justification for VPN permission
