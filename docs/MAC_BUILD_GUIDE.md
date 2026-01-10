# Mac 本地 iOS 构建指南

## 环境准备

### 1. 安装 Xcode
```bash
# 从 App Store 安装 Xcode (需要 Xcode 15+)
# 或者下载: https://developer.apple.com/xcode/

# 安装命令行工具
xcode-select --install
```

### 2. 安装 Flutter
```bash
# 使用 Homebrew 安装
brew install flutter

# 或者手动安装
cd ~
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$HOME/flutter/bin:$PATH"

# 添加到 ~/.zshrc 或 ~/.bash_profile
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 验证安装
flutter doctor
```

### 3. 安装 CocoaPods
```bash
brew install cocoapods
# 或
sudo gem install cocoapods
```

---

## 克隆项目

```bash
# 克隆仓库
cd ~/Desktop
git clone https://github.com/EdNovas/ednovas_clash_mobile.git
cd ednovas_clash_mobile

# 安装依赖
flutter pub get

# 安装 iOS 依赖
cd ios
pod install
cd ..
```

---

## 配置签名 (一次性设置)

### 1. 打开 Xcode
```bash
open ios/Runner.xcworkspace
```

### 2. 配置 Runner Target
1. 在左侧选择 **Runner** 项目 (蓝色图标)
2. 选择 **Runner** target
3. 点击 **Signing & Capabilities** tab
4. **勾选** "Automatically manage signing"
5. 选择你的 **Team** (需要 Apple Developer 账号)
6. 如果 Bundle Identifier 有冲突，改成你自己的 ID

### 3. 配置 PacketTunnelExtension Target
1. 选择 **PacketTunnelExtension** target
2. 点击 **Signing & Capabilities** tab
3. **勾选** "Automatically manage signing"
4. 选择相同的 **Team**
5. 确保 Bundle Identifier 是主 app 的子 ID (如 `com.yourcompany.app.PacketTunnel`)

### 4. 配置 App Groups (VPN 需要)
对 **Runner** 和 **PacketTunnelExtension** 两个 target:
1. 点击 **Signing & Capabilities**
2. 点击 **+ Capability**
3. 添加 **App Groups**
4. 添加 group: `group.com.ednovas.clash` (或你自己的)

### 5. 配置 Network Extension
对 **PacketTunnelExtension** target:
1. 添加 **Network Extensions** capability
2. 勾选 **Packet Tunnel**

---

## 本地测试

### 模拟器测试
```bash
# 列出可用模拟器
flutter devices

# 在模拟器上运行
flutter run -d "iPhone 15 Pro"
```

### 真机测试
1. 用 USB 连接 iPhone
2. 信任电脑
3. 在 Xcode 中选择你的设备
4. 运行:
```bash
flutter run -d <你的设备ID>
```

**注意**: 真机第一次运行需要在 iPhone 设置中信任开发者证书：
- 设置 → 通用 → VPN与设备管理 → 信任开发者

---

## 构建 IPA

### Debug 构建 (测试用)
```bash
flutter build ios --debug
```

### Release 构建 (发布用)
```bash
# 不签名构建 (用于 CI)
flutter build ios --release --no-codesign

# 打开 Xcode 进行归档
open ios/Runner.xcworkspace
```

### Xcode 归档发布
1. 在 Xcode 中: **Product → Archive**
2. 等待归档完成
3. 打开 **Organizer** (Window → Organizer)
4. 选择刚才的归档
5. 点击 **Distribute App**
6. 选择:
   - **App Store Connect** → 上传到 TestFlight
   - **Ad Hoc** → 生成 IPA 分发测试
   - **Development** → 开发测试

---

## 常见问题

### Pod install 失败
```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install --repo-update
```

### 签名错误
1. 确保 Apple Developer 账号有效
2. 在 Xcode 中: Xcode → Preferences → Accounts → 登录账号
3. 重新选择 Team

### 构建缓存问题
```bash
flutter clean
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter pub get
flutter build ios
```

### Network Extension 权限
需要在 Apple Developer Portal 中为你的 App ID 启用:
- Network Extensions
- App Groups

---

## 提交更改

完成本地测试后，提交 Xcode 的配置更改：

```bash
git add .
git commit -m "feat: configure iOS signing and capabilities"
git push
```

**重要**: `ios/Runner.xcodeproj/project.pbxproj` 包含签名配置，需要提交。

---

## 发布到 TestFlight

### 方法 1: Xcode 直接上传
1. **Product → Archive**
2. **Distribute App → App Store Connect**
3. 按提示上传

### 方法 2: 命令行 (需要 API Key)
```bash
# 构建
flutter build ipa --release

# 上传
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/EdNovas-Clash.ipa \
  --apiKey YOUR_API_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID
```

---

## 快速命令参考

```bash
# 完整构建流程
flutter clean && flutter pub get && cd ios && pod install && cd .. && flutter build ios --release

# 运行调试
flutter run

# 打开 Xcode
open ios/Runner.xcworkspace

# 检查环境
flutter doctor -v
```
