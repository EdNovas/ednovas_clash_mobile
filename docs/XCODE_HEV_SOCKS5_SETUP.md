# Xcode 配置步骤：集成 hev-socks5-tunnel

## 概述

我们已经创建了基于 `hev-socks5-tunnel` (C 实现) 的 `Socks5Tunnel` 来替代不工作的 `go-tun2socks`。

这个 C 库可以在 iOS Network Extension 中正常工作，因为它直接使用 BSD sockets，不会遇到 Go 的 net.Dial 无法连接 localhost 的问题。

## 需要在 Xcode 中完成的步骤

### 步骤 1: 添加 HevSocks5Tunnel.xcframework

1. 在 Xcode 中打开项目 (`ios/Runner.xcworkspace`)
2. 在左侧项目导航器中选择 **Runner** 项目
3. 选择 **PacketTunnelExtension** target
4. 点击 **General** 标签
5. 滚动到 **Frameworks, Libraries, and Embedded Content**
6. 点击 **+** 按钮
7. 选择 **Add Other... → Add Files...**
8. 导航到 `ios/HevSocks5Tunnel.xcframework` 并添加
9. 确保 "Embed" 设置为 **Do Not Embed** (因为是静态库)

### 步骤 2: 添加 Socks5Tunnel.swift

1. 在项目导航器中右键点击 **PacketTunnelExtension** 文件夹
2. 选择 **Add Files to "Runner"...**
3. 选择 `ios/PacketTunnelExtension/Socks5Tunnel.swift`
4. 确保仅勾选 **PacketTunnelExtension** target
5. 点击 **Add**

### 步骤 3: 验证桥接头文件

桥接头文件 (`PacketTunnelExtension-Bridging-Header.h`) 已经更新，包含了：
- Clash Core 函数声明
- Go tun2socks 函数声明 (备用)
- **hev-socks5-tunnel 函数声明** (新加)
- TUN fd 发现所需的类型定义

确保在 Build Settings 中 `Objective-C Bridging Header` 指向正确的文件：
`PacketTunnelExtension/PacketTunnelExtension-Bridging-Header.h`

### 步骤 4: 清理并构建

1. 清理项目: **Product → Clean Build Folder** (Cmd+Shift+K)
2. 构建项目: **Product → Build** (Cmd+B)

## 工作原理

新的实现流程：

1. **PacketTunnelProvider.startTun2socks()** 首先尝试使用 `Socks5Tunnel` (C 实现)
2. `Socks5Tunnel.tunnelFileDescriptor` 遍历所有打开的文件描述符，找到 TUN 接口
3. 如果找到 TUN fd，使用 `hev_socks5_tunnel_main_from_str()` 启动 C 隧道
4. C 隧道直接读写 TUN fd，将 TCP/UDP 流量转发到 SOCKS5 代理 (Clash)
5. 如果找不到 TUN fd，回退到 Go 实现 (可能不工作)

## 预期日志

成功时应该看到：
```
✅ [PacketTunnel] Found TUN fd: XX, using hev-socks5-tunnel (C implementation)
🚀 [Tun2Socks] Starting with fd=XX
```

如果 C 实现不可用：
```
❌ [PacketTunnel] Could not find TUN file descriptor, falling back to Go tun2socks
```

## 故障排除

### 问题: 找不到 HevSocks5Tunnel.xcframework
确保文件在 `ios/HevSocks5Tunnel.xcframework` 目录下

### 问题: 链接错误
检查 Build Phases → Link Binary With Libraries 中是否包含 HevSocks5Tunnel.xcframework

### 问题: 桥接头文件错误
确保 C 函数声明与 HevSocks5Tunnel.xcframework 中的头文件匹配
