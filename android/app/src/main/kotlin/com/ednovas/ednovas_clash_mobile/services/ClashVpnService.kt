package com.ednovas.ednovas_clash_mobile.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ednovas.ednovas_clash_mobile.MainActivity
import com.ednovas.ednovas_clash_mobile.R
import java.io.File

class ClashVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.ednovas.ednovas_clash_mobile.START"
        const val ACTION_STOP = "com.ednovas.ednovas_clash_mobile.STOP"
        const val ACTION_RESTART = "com.ednovas.ednovas_clash_mobile.RESTART"
        const val ACTION_UPDATE_INFO = "com.ednovas.ednovas_clash_mobile.UPDATE_INFO"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "ClashVpnServiceChannel"
        
        @Volatile var isRunning = false
        
        // JNA Interface definition
        interface ClashLibrary : com.sun.jna.Library {
            fun Start(homeDir: String, configContent: String, fd: Int): String?
            fun startTUN(callback: com.sun.jna.Pointer?, fd: Int, stack: String, address: String, dns: String): Boolean
            fun Stop(): String?
            fun SetMode(mode: String): String?
            fun GetMode(): String?
        }
        
        // Shared library instance
        val clashLib: ClashLibrary by lazy {
            com.sun.jna.Native.load("clash", ClashLibrary::class.java)
        }
        
        // Helper methods for external access
        fun setMode(mode: String): String? {
            return try {
                clashLib.SetMode(mode)
            } catch (e: Exception) {
                "Error: ${e.message}"
            }
        }
        
        fun getMode(): String? {
            return try {
                clashLib.GetMode()
            } catch (e: Exception) {
                null
            }
        }
    }

    private var tunFd: ParcelFileDescriptor? = null
    private val TAG = "ClashVpnService"

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        
        // Handle Stop Action
        if (action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }

        // Handle Restart Action
        if (action == ACTION_RESTART) {
            Log.d(TAG, "Restart requested")
            restartService()
            return START_STICKY
        }

        // Handle Update Info
        if (action == ACTION_UPDATE_INFO) {
            val node = intent?.getStringExtra("node") ?: ""
            val speed = intent?.getStringExtra("speed") ?: ""
            updateNotification(node, speed)
            return START_STICKY
        }

        // 1. Immediately start Foreground to keep service alive
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification("Connected", ""))

        val configPath = intent?.getStringExtra("config_path")
        if (configPath != null) {
            startClashAsync(configPath)
        } else {
            // Only stop if we are trying to START but have no config. 
            // If we are just updating info, we shouldn't be here (caught above).
            // But if action is START and no config, then error.
            if (action == ACTION_START) {
                 Log.e(TAG, "No config_path provided")
                 stopSelf()
            }
        }
        
        return START_STICKY
    }
    
    private fun startClashAsync(configPath: String) {
        if (isRunning) {
            Log.w(TAG, "Clash is already running")
            return
        }
        isRunning = true
        
        Thread {
            Log.d(TAG, "Starting Clash in background thread with config: $configPath")
            
            // Validate file
            val configFile = File(configPath)
            if (!configFile.exists()) {
                Log.e(TAG, "Config file not found")
                stopVpn()
                return@Thread
            }
            
            val configContent = configFile.readText()
            val homeDir = configFile.parentFile.absolutePath

            // Establish VPN
            if (!establishVpn()) {
                Log.e(TAG, "VPN Establishment failed")
                stopVpn()
                return@Thread
            }

            // Start Go Core
            try {
                Log.d(TAG, "Calling Native Start (Init Hub)...")
                // Call Start with fd=0 to only initialize Hub/Config but NOT start TUN
                val initError = clashLib.Start(homeDir, configContent, 0)
                if (!initError.isNullOrEmpty()) {
                    Log.e(TAG, "Native Init returned error: $initError")
                    stopVpn()
                    return@Thread
                }

                Log.d(TAG, "Calling Native startTUN...")
                // Use detachFd() to transfer ownership of the fd to Go code
                // After detachFd(), ParcelFileDescriptor will no longer try to close the fd
                val fd = tunFd!!.detachFd()
                tunFd = null  // Clear reference since we've detached it
                
                // Pass explicit parameters to startTUN (gvisor is recommended for Android)
                val success = clashLib.startTUN(null, fd, "gvisor", "172.19.0.1/30", "1.1.1.1,8.8.8.8")
                
                if (!success) {
                    Log.e(TAG, "Native startTUN Failed")
                    stopVpn()
                } else {
                    Log.d(TAG, "Clash Core started successfully")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error starting Clash Core: ${e.message}", e)
                stopVpn()
            }
        }.start()
    }

    private fun establishVpn(): Boolean {
        return try {
            val builder = Builder()
            builder.setMtu(9000)
            builder.setSession("Clash VPN")
            
            // IPv4 Setup
            builder.addAddress("172.19.0.1", 30)
            builder.addRoute("0.0.0.0", 0)
            
            // IPv6 Setup (Prevent Leak)
            builder.addAddress("fd00::1", 126)
            builder.addRoute("::", 0)
            
            // DNS
            builder.addDnsServer("1.1.1.1")
            
            // Configure Intent
            val pendingIntent = PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE
            )
            builder.setConfigureIntent(pendingIntent)

            // Attempt to exclude self to avoid loop
            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to exclude sensitive app: ${e.message}")
            }

            tunFd = builder.establish()
            tunFd != null
        } catch (e: Exception) {
            Log.e(TAG, "Error building VPN", e)
            false
        }
    }

    private fun stopVpn() {
        isRunning = false
        
        // First, stop the Go core - this will close the TUN listener and the fd
        try {
            clashLib.Stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping Clash: ${e.message}")
        }
        
        // Don't close tunFd here! 
        // The fd ownership was transferred to Go when we passed it to startTUN.
        // Go's tunListener.Close() already closed the fd.
        // Calling tunFd.close() again would cause fdsan error.
        tunFd = null
        
        stopForeground(true)
        stopSelf()
        Log.d(TAG, "VPN Service destroyed")
    }

    private fun restartService() {
        Log.d(TAG, "Restarting VPN service...")
        
        // Stop the core first
        try {
            clashLib.Stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping Clash for restart: ${e.message}")
        }
        
        tunFd = null
        isRunning = false
        
        // Get the config path from shared preferences or cache
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val configPath = prefs.getString("flutter.cached_config_path", null) 
            ?: filesDir.absolutePath + "/clash/config.yaml"
        
        Log.d(TAG, "Restarting with config: $configPath")
        
        // Restart after a short delay
        Thread {
            Thread.sleep(500)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                startClashAsync(configPath)
            }
        }.start()
    }

    private fun updateNotification(node: String, speed: String) {
        if (!isRunning) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, createNotification(node, speed))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Clash VPN Service",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(node: String, speed: String): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        // Stop action
        val stopIntent = Intent(this, ClashVpnService::class.java)
        stopIntent.action = ACTION_STOP
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent, 
            PendingIntent.FLAG_IMMUTABLE
        )

        // Restart action
        val restartIntent = Intent(this, ClashVpnService::class.java)
        restartIntent.action = ACTION_RESTART
        val restartPendingIntent = PendingIntent.getService(
            this, 2, restartIntent, 
            PendingIntent.FLAG_IMMUTABLE
        )

        // Bilingual support
        val isZh = java.util.Locale.getDefault().language == "zh"
        val stopText = if (isZh) "停止" else "Stop"
        val restartText = if (isZh) "重启服务" else "Service restart"
        
        // Content text: show node name, and speed if available
        val contentText = if (node.isNotEmpty() && speed.isNotEmpty()) {
            "$node  $speed"
        } else if (node.isNotEmpty()) {
            node
        } else {
            if (isZh) "已连接" else "Connected"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EdNovas Clash")
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .addAction(0, stopText, stopPendingIntent)
            .addAction(0, restartText, restartPendingIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}
