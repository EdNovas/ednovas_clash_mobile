# Google Play Store 上架指南

本文档详细说明在 Google Play Store 上架 EdNovas云 需要准备的内容和步骤。

## 📋 准备清单

### 1. 应用图标 (App Icon)

**你的 icon.png 需要处理成以下尺寸并放到对应目录：**

| 目录 | 尺寸 (px) | 说明 |
|------|-----------|------|
| `mipmap-mdpi` | 48x48 | 中等密度屏幕 |
| `mipmap-hdpi` | 72x72 | 高密度屏幕 |
| `mipmap-xhdpi` | 96x96 | 超高密度屏幕 |
| `mipmap-xxhdpi` | 144x144 | 超超高密度屏幕 |
| `mipmap-xxxhdpi` | 192x192 | 超超超高密度屏幕 |

**快速处理方法：**

1. **使用 Android Studio**
   - 右键 `res` 文件夹 → New → Image Asset
   - 选择你的 icon.png，它会自动生成所有尺寸

2. **在线工具**
   - [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/icons-launcher.html)
   - [App Icon Generator](https://appicon.co/)

3. **命令行 (需要 ImageMagick)**
   ```bash
   # 安装 ImageMagick
   # Windows: winget install ImageMagick
   # macOS: brew install imagemagick
   # Linux: sudo apt install imagemagick
   
   # 生成所有尺寸
   convert icon.png -resize 48x48 android/app/src/main/res/mipmap-mdpi/ic_launcher.png
   convert icon.png -resize 72x72 android/app/src/main/res/mipmap-hdpi/ic_launcher.png
   convert icon.png -resize 96x96 android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
   convert icon.png -resize 144x144 android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
   convert icon.png -resize 192x192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
   ```

4. **Flutter 插件 (推荐)**
   ```yaml
   # pubspec.yaml 中添加
   dev_dependencies:
     flutter_launcher_icons: ^0.13.1
   
   flutter_launcher_icons:
     android: true
     ios: false
     image_path: "assets/icon.png"
   ```
   然后运行：
   ```bash
   flutter pub get
   flutter pub run flutter_launcher_icons
   ```

### 2. 签名密钥 (Signing Key)

**⚠️ 重要：请妥善保管密钥，丢失后无法更新应用！**

```bash
# 生成签名密钥
keytool -genkey -v -keystore ednovas-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias ednovas
```

创建 `android/key.properties`（已添加到 .gitignore）：
```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=ednovas
storeFile=../ednovas-release-key.jks
```

更新 `android/app/build.gradle.kts` 添加签名配置：
```kotlin
// 在 android 块之前添加
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

### 3. Play Console 资产

| 资产 | 尺寸要求 | 说明 |
|------|----------|------|
| 应用图标 | 512x512 PNG | 高清图标（无 Alpha） |
| 功能图 | 1024x500 PNG/JPEG | 应用在 Play Store 的横幅 |
| 手机截图 | 16:9 或 9:16 | 至少 2 张，最多 8 张 |
| 平板截图 | 可选 | 7 英寸和 10 英寸平板 |

### 4. 应用详情

**标题 (最多 30 字符)**
```
EdNovas云 - VPN代理客户端
```

**简短描述 (最多 80 字符)**
```
EdNovas订阅专属VPN客户端，一键连接，智能分流，安全稳定。
```

**完整描述 (最多 4000 字符)**
```
EdNovas云是专为EdNovas订阅用户设计的VPN客户端应用。

✨ 主要功能：
• 一键登录 - 使用EdNovas账号直接登录
• 自动配置 - 自动获取并更新代理配置
• TUN模式 - 系统级代理，全局流量接管
• 智能分流 - 根据规则自动选择最优线路
• 节点切换 - 支持手动选择代理节点
• 实时监控 - 查看连接状态和流量统计

🔒 安全特性：
• 基于Clash Meta核心，稳定可靠
• 支持多种代理协议
• 本地DNS解析，防止泄露

📱 用户体验：
• Material Design 3 现代界面
• 深色/浅色主题自动切换
• 简洁直观的操作流程

⚠️ 注意：本应用需要有效的EdNovas订阅才能使用。
```

### 5. 隐私政策

**必须提供隐私政策 URL！** 你可以：

1. 在 GitHub Pages 上托管
2. 使用 Notion 公开页面
3. 创建专门的网页

示例隐私政策要点：
- 收集的数据类型（账号信息、网络流量统计）
- 数据使用目的
- 数据存储和保护措施
- 第三方服务
- 用户权利
- 联系方式

### 6. 内容分级

完成 Google Play 内容分级问卷：
- 应用类型：工具
- 暴力内容：无
- 色情内容：无
- 语言：无粗俗语言
- 受控物质：无
- 用户生成内容：无

### 7. 目标受众

- **目标年龄段**：13 岁及以上
- **非儿童应用**

### 8. VPN 特殊要求

由于是 VPN 应用，Google 有额外要求：

1. **政策遵守**
   - 不能用于绕过付费内容
   - 不能违反当地法律
   - 必须明确披露 VPN 功能

2. **权限说明**
   - 需要解释为什么需要 VPN 权限
   - 在应用内或商店描述中说明

3. **隐私增强**
   - 明确说明是否记录流量
   - 说明数据加密方式

## 📤 发布流程

### 1. 注册 Google Play 开发者账号
- 费用：$25 美元（一次性）
- 网址：https://play.google.com/console

### 2. 创建应用
- 选择"创建应用"
- 填写应用名称、语言
- 选择应用类型（应用/游戏）

### 3. 填写商店详情
- 上传图标和截图
- 填写描述
- 设置分类和标签

### 4. 设置内容分级
- 完成分级问卷

### 5. 设置定价和分发
- 选择免费/付费
- 选择发布国家/地区

### 6. 构建发布版本
```bash
# 构建 App Bundle (推荐)
flutter build appbundle --release

# 或构建 APK
flutter build apk --release --split-per-abi
```

### 7. 上传并审核
- 上传 AAB 或 APK
- 提交审核
- 等待 3-7 天（首次可能更长）

## ⚠️ 常见拒绝原因

1. **缺少隐私政策**
2. **VPN 功能声明不完整**
3. **违反 VPN 相关政策**
4. **元数据问题**（标题含敏感词）
5. **功能不完整或崩溃**

## 📁 项目文件位置总结

```
ednovas_clash_mobile/
├── assets/
│   └── icon.png              # 放置原始图标
├── android/
│   ├── key.properties        # 签名配置（不提交到 Git）
│   ├── ednovas-release-key.jks  # 签名密钥（不提交到 Git）
│   └── app/src/main/res/
│       ├── mipmap-mdpi/
│       │   └── ic_launcher.png   # 48x48
│       ├── mipmap-hdpi/
│       │   └── ic_launcher.png   # 72x72
│       ├── mipmap-xhdpi/
│       │   └── ic_launcher.png   # 96x96
│       ├── mipmap-xxhdpi/
│       │   └── ic_launcher.png   # 144x144
│       └── mipmap-xxxhdpi/
│           └── ic_launcher.png   # 192x192
└── docs/
    ├── screenshots/          # 商店截图
    └── privacy-policy.md     # 隐私政策
```

## 🔗 有用链接

- [Google Play Console](https://play.google.com/console)
- [Android 发布指南](https://developer.android.com/studio/publish)
- [Flutter 发布文档](https://docs.flutter.dev/deployment/android)
- [VPN 应用政策](https://support.google.com/googleplay/android-developer/answer/9878000)
