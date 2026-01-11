# EdNovas云 (EdNovas Clash Mobile)

<div align="center">

<img src="assets/icon.png" width="120" alt="EdNovas云 Logo"/>

![Version](https://img.shields.io/badge/version-v1.0.23-blue)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-green)
![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-MIT-orange)

**EdNovas 订阅服务专属 VPN 客户端**

[下载](#-下载) • [功能](#-功能) • [截图](#-截图) • [开发](#-开发) • [许可证](#-许可证)

</div>

---

## 📱 简介

EdNovas云 是一款专为 [EdNovas](https://ednovas.com) 订阅用户设计的 Android VPN 客户端。基于 [Mihomo](https://github.com/MetaCubeX/mihomo) (Clash Meta) 核心，参考 [FlClash](https://github.com/chen08209/FlClash) 架构设计，提供高效、稳定的代理服务。

## ✨ 功能

- 🔐 **一键登录** - 使用 EdNovas 账号直接登录
- 🚀 **自动配置** - 自动获取并更新订阅配置
- 🌐 **TUN 模式** - 系统级代理，全局流量接管
- 📊 **流量统计** - 实时显示连接状态和流量信息
- 🎯 **智能分流** - 根据规则自动选择最优节点
- 🔄 **节点切换** - 支持手动切换代理节点
- 📱 **现代 UI** - Material Design 3 风格界面

## 📦 下载

从 [Releases](https://github.com/EdNovas/ednovas_clash_mobile/releases) 页面下载最新版本：

| 文件名 | 架构 | 说明 |
|--------|------|------|
| `EdNovas-Clash-vX.X.X-arm64-v8a.apk` | ARM64 | 大多数现代手机（推荐） |
| `EdNovas-Clash-vX.X.X-armeabi-v7a.apk` | ARM32 | 较旧的 32 位手机 |
| `EdNovas-Clash-vX.X.X-x86_64.apk` | x86_64 | 模拟器、部分平板 |
| `EdNovas-Clash-vX.X.X-universal.apk` | 通用 | 包含所有架构（文件较大） |

> 💡 不确定选哪个？选择 `arm64-v8a` 版本，适用于 2016 年后发布的大多数 Android 手机。

## 📸 截图

<div align="center">
<table>
  <tr>
    <td><img width="200" alt="登录页面" src="https://github.com/user-attachments/assets/1162fa79-df6f-4994-8e73-40fd7e088710" />
</td>
    <td><img width="200" alt="主页" src="https://github.com/user-attachments/assets/21218082-17d5-4e9f-bd58-574391191259" />
</td>
    <td><img width="200" alt="节点选择" src="https://github.com/user-attachments/assets/5bbe6bf3-ca6c-499f-a9f4-5f86dd91f4d9" />
</td>
  </tr>
  <tr>
    <td align="center">登录</td>
    <td align="center">主页</td>
    <td align="center">节点</td>
  </tr>
</table>
</div>

## 🛠 开发

### 环境要求

- Flutter 3.24+
- Go 1.22+
- **Android**: Android SDK & NDK r26b, Java 17
- **iOS**: Xcode 15+, macOS Sonoma+

### 本地编译

1. **克隆仓库**
   ```bash
   git clone https://github.com/EdNovas/ednovas_clash_mobile.git
   cd ednovas_clash_mobile
   ```

2. **编译核心库**

   **Android (Go → .so):**
   
   Windows (PowerShell):
   ```powershell
   .\build_so.ps1
   ```
   
   Linux/macOS:
   ```bash
   cd core
   CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
     CC=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang \
     go build -buildmode=c-shared -tags "with_gvisor,cmfa" -ldflags="-s -w" \
     -o ../android/app/src/main/jniLibs/arm64-v8a/libclash.so .
   ```

   **iOS (Go → .xcframework):**
   ```bash
   cd core
   ./build_ios.sh
   # 输出到: ios/Clashcore.xcframework/
   ```

3. **编译 Flutter App**
   
   **Android:**
   ```bash
   flutter pub get
   flutter build apk --release
   ```
   
   **iOS:**
   ```bash
   flutter pub get
   flutter build ios --release
   # 然后在 Xcode 中: Product → Archive
   ```

### 项目结构

```
ednovas_clash_mobile/
├── android/                 # Android 原生代码
│   └── app/src/main/
│       ├── kotlin/          # Kotlin VPN 服务
│       └── jniLibs/         # 编译后的 .so 文件
├── ios/                     # iOS 原生代码
│   ├── Runner/              # Flutter iOS App
│   ├── PacketTunnelExtension/ # Network Extension
│   └── Clashcore.xcframework/ # 编译后的核心库
├── core/                    # Go 核心代码
│   ├── lib.go              # Android JNI 接口
│   ├── ios/                # iOS C 接口
│   ├── tun/                # TUN 模块
│   ├── build_ios.sh        # iOS 构建脚本
│   └── go.mod              # Go 依赖
├── lib/                     # Flutter 代码
│   ├── main.dart           # 入口
│   ├── pages/              # 页面
│   ├── services/           # 服务
│   └── widgets/            # 组件
└── .github/workflows/       # CI/CD 配置
```

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源。

## 🙏 致谢

- [FlClash](https://github.com/chen08209/FlClash) - 项目架构设计参考，优秀的跨平台 Clash 客户端
- [Mihomo](https://github.com/MetaCubeX/mihomo) - Clash Meta 核心引擎
- [sing-tun](https://github.com/SagerNet/sing-tun) - TUN 接口实现
- [Flutter](https://flutter.dev/) - 跨平台 UI 框架

---

<div align="center">

**[EdNovas](https://ednovas.com)** - 稳定、高速、安全的代理服务

Made with ❤️ by EdNovas Team

</div>
