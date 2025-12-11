package com.ednovas.ednovas_clash_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import com.ednovas.ednovas_clash_mobile.services.ClashVpnService

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ednovas.clash/vpn"
    private var pendingConfigPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "start") {
                val configPath = call.argument<String>("config_path") ?: ""
                val intent = android.net.VpnService.prepare(this)
                if (intent != null) {
                    pendingConfigPath = configPath
                    startActivityForResult(intent, 0)
                    // Don't return error, just waiting for user interaction. 
                    // Or return error so Flutter knows permission is being asked.
                    result.error("PERMISSION_REQUIRED", "VPN Permission required", null)
                } else {
                    startVpnService(configPath)
                    result.success("VPN Started")
                }
            } else if (call.method == "stop") {
                val intent = android.content.Intent(this, ClashVpnService::class.java)
                intent.action = ClashVpnService.ACTION_STOP
                startService(intent)
                result.success("VPN Stopped")
            } else if (call.method == "status") {
                val isRunning = ClashVpnService.isRunning
                result.success(isRunning)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startVpnService(configPath: String) {
        val intent = android.content.Intent(this, ClashVpnService::class.java)
        intent.putExtra("config_path", configPath)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0 && resultCode == android.app.Activity.RESULT_OK) {
            val path = pendingConfigPath ?: ""
            if (path.isNotEmpty()) {
                startVpnService(path)
            }
            pendingConfigPath = null
        }
    }
}
