//go:build android && cmfa

// Package main provides stub implementations for Android CMFA builds.
// When building with the 'cmfa' tag, the original server_android.go is excluded
// because it has `//go:build android && !cmfa`. This file provides the necessary
// stub functions to prevent the app from trying to read /data/system/packages.xml.
package main

// Note: The actual stub implementations for the Listener methods are handled
// by mihomo when building with cmfa tag. However, if mihomo doesn't provide
// stubs, we may need to fork and modify mihomo to add cmfa stubs.
//
// The cmfa build tag is used by ClashMetaForAndroid (CMFA) to disable
// package-based routing rules that require reading system files.
