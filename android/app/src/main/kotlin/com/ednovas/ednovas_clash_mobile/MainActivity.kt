package com.ednovas.ednovas_clash_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.VpnService
import android.os.Build
import com.ednovas.ednovas_clash_mobile.services.ClashVpnService

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ednovas.clash/vpn"
    private var pendingConfigPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val configPath = call.argument<String>("config_path")
                    if (configPath == null) {
                        result.error("INVALID_ARGUMENT", "Config path is null", null)
                        return@setMethodCallHandler
                    }

                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        // Permission required
                        pendingConfigPath = configPath
                        startActivityForResult(intent, 0)
                        result.error("PERMISSION_REQUIRED", "VPN Permission required", null)
                    } else {
                        // Permission granted
                        startVpnService(configPath)
                        result.success(true)
                    }
                }
                "stop" -> {
                    val intent = Intent(this, ClashVpnService::class.java)
                    intent.action = ClashVpnService.ACTION_STOP
                    startService(intent)
                    result.success(true)
                }
                "status" -> {
                    result.success(ClashVpnService.isRunning)
                }
                "setMode" -> {
                    val mode = call.argument<String>("mode")
                    if (mode == null) {
                        result.error("INVALID_ARGUMENT", "Mode is null", null)
                        return@setMethodCallHandler
                    }
                    val error = ClashVpnService.setMode(mode)
                    if (error.isNullOrEmpty()) {
                        result.success(true)
                    } else {
                        result.error("SET_MODE_FAILED", error, null)
                    }
                }
                "getMode" -> {
                    val mode = ClashVpnService.getMode()
                    result.success(mode ?: "unknown")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startVpnService(configPath: String) {
        val intent = Intent(this, ClashVpnService::class.java)
        intent.action = ClashVpnService.ACTION_START
        intent.putExtra("config_path", configPath)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0 && resultCode == RESULT_OK) {
            val path = pendingConfigPath
            if (path != null) {
                startVpnService(path)
            }
            pendingConfigPath = null
        }
    }
}
