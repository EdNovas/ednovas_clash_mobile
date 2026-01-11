#!/bin/bash
# ============================================
# GitHub Actions 配置导出脚本
# EdNovas Clash iOS
# ============================================

set -e

OUTPUT_DIR="$HOME/Desktop/github-secrets"
mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "  GitHub Actions Secrets 导出工具"
echo "========================================"
echo ""

# ============================================
# 步骤 1: 查找 Distribution 证书
# ============================================
echo "📦 步骤 1: 导出 Distribution 证书"
echo "----------------------------------------"

# 列出可用的证书
echo "找到的证书:"
security find-identity -v -p codesigning | grep "Apple Distribution" || echo "未找到 Apple Distribution 证书"
echo ""

echo "⚠️  请手动导出证书:"
echo "   1. 打开 钥匙串访问 (Keychain Access)"
echo "   2. 左侧选择 '登录' → '我的证书'"
echo "   3. 找到 'Apple Distribution: xxx' 证书"
echo "   4. 右键 → 导出..."
echo "   5. 保存到: $OUTPUT_DIR/certificate.p12"
echo "   6. 设置一个密码并记住它"
echo ""
read -p "按 Enter 继续..." 

# ============================================
# 步骤 2: 转换证书为 Base64
# ============================================
if [ -f "$OUTPUT_DIR/certificate.p12" ]; then
    echo "✅ 找到证书文件，转换为 Base64..."
    base64 -i "$OUTPUT_DIR/certificate.p12" -o "$OUTPUT_DIR/DISTRIBUTION_CERTIFICATE_BASE64.txt"
    echo "✅ 证书 Base64 已保存到: $OUTPUT_DIR/DISTRIBUTION_CERTIFICATE_BASE64.txt"
else
    echo "❌ 未找到证书文件: $OUTPUT_DIR/certificate.p12"
    echo "   请先导出证书后重新运行此脚本"
fi

echo ""

# ============================================
# 步骤 3: 查找并导出 Provisioning Profiles
# ============================================
echo "📦 步骤 2: 导出 Provisioning Profiles"
echo "----------------------------------------"

PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

echo "查找 Provisioning Profiles..."
echo ""

# 查找包含我们 Bundle ID 的 profiles
for profile in "$PROFILES_DIR"/*.mobileprovision; do
    if [ -f "$profile" ]; then
        # 提取 profile 名称
        name=$(/usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin 2>/dev/null <<< $(security cms -D -i "$profile" 2>/dev/null) || echo "Unknown")
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /dev/stdin 2>/dev/null <<< $(security cms -D -i "$profile" 2>/dev/null) || echo "Unknown")
        
        if [[ "$bundle_id" == *"ednovasClashMobile"* ]]; then
            echo "✅ 找到相关 Profile:"
            echo "   名称: $name"
            echo "   Bundle ID: $bundle_id"
            echo "   文件: $(basename "$profile")"
            
            if [[ "$bundle_id" == *"PacketTunnelExtension"* ]]; then
                echo "   → 这是 Extension Profile"
                cp "$profile" "$OUTPUT_DIR/extension.mobileprovision"
                base64 -i "$profile" -o "$OUTPUT_DIR/EXTENSION_PROVISIONING_PROFILE_BASE64.txt"
            else
                echo "   → 这是 Runner Profile"
                cp "$profile" "$OUTPUT_DIR/runner.mobileprovision"
                base64 -i "$profile" -o "$OUTPUT_DIR/RUNNER_PROVISIONING_PROFILE_BASE64.txt"
            fi
            echo ""
        fi
    fi
done

echo ""

# ============================================
# 步骤 4: App Store Connect API Key
# ============================================
echo "📦 步骤 3: App Store Connect API Key"
echo "----------------------------------------"
echo ""
echo "⚠️  请手动创建 API Key:"
echo "   1. 打开 https://appstoreconnect.apple.com/access/api"
echo "   2. 点击 '+' 创建新 Key"
echo "   3. 名称: GitHub Actions"
echo "   4. 权限: App Manager"
echo "   5. 下载 .p8 文件到: $OUTPUT_DIR/AuthKey.p8"
echo "   6. 记录 Key ID 和 Issuer ID"
echo ""
read -p "按 Enter 继续..."

if [ -f "$OUTPUT_DIR/AuthKey.p8" ]; then
    echo "✅ 找到 API Key 文件，转换为 Base64..."
    base64 -i "$OUTPUT_DIR/AuthKey.p8" -o "$OUTPUT_DIR/APP_STORE_CONNECT_API_KEY_CONTENT.txt"
    echo "✅ API Key Base64 已保存"
else
    # 查找可能的 AuthKey 文件
    for key in "$OUTPUT_DIR"/AuthKey*.p8; do
        if [ -f "$key" ]; then
            echo "✅ 找到 API Key: $key"
            base64 -i "$key" -o "$OUTPUT_DIR/APP_STORE_CONNECT_API_KEY_CONTENT.txt"
            echo "✅ API Key Base64 已保存"
            break
        fi
    done
fi

echo ""

# ============================================
# 总结
# ============================================
echo "========================================"
echo "  📋 导出完成！"
echo "========================================"
echo ""
echo "导出目录: $OUTPUT_DIR"
echo ""
echo "文件列表:"
ls -la "$OUTPUT_DIR" 2>/dev/null || echo "目录为空"
echo ""
echo "========================================"
echo "  🔑 需要添加到 GitHub Secrets 的内容:"
echo "========================================"
echo ""
echo "Secret 名称                              | 值来源"
echo "-----------------------------------------|------------------"
echo "DISTRIBUTION_CERTIFICATE_BASE64          | certificate_base64.txt 的内容"
echo "DISTRIBUTION_CERTIFICATE_PASSWORD        | 您设置的证书密码"
echo "RUNNER_PROVISIONING_PROFILE_BASE64       | runner_profile_base64.txt 的内容"
echo "EXTENSION_PROVISIONING_PROFILE_BASE64    | extension_profile_base64.txt 的内容"
echo "APP_STORE_CONNECT_API_KEY_ID             | API Key ID (在网站上查看)"
echo "APP_STORE_CONNECT_API_ISSUER_ID          | Issuer ID (在网站上查看)"
echo "APP_STORE_CONNECT_API_KEY_CONTENT        | api_key_base64.txt 的内容"
echo ""
echo "打开目录查看文件:"
open "$OUTPUT_DIR"
