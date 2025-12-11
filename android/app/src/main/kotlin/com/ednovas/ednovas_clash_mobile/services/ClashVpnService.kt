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
import com.sun.jna.Callback
import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import org.json.JSONObject

interface ClashCallback : Callback {
    fun invoke(result: String)
}

interface ClashLibrary : Library {
    fun invokeAction(callback: ClashCallback, params: String)
    fun startTUN(callback: ClashCallback?, fd: Int, stack: String, address: String, dns: String): Boolean
    fun stopTun()
}

class ClashVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.ednovas.ednovas_clash_mobile.START"
        const val ACTION_STOP = "com.ednovas.ednovas_clash_mobile.STOP"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "ClashVpnServiceChannel"
        
        val INSTANCE: ClashLibrary by lazy {
            Native.load("clash", ClashLibrary::class.java)
        }
    }

    private var tunFd: ParcelFileDescriptor? = null
    private val TAG = "ClashVpnService"
    private var isRunning = false

    // Keep reference to callback to prevent GC
    private val clashCallback = object : ClashCallback {
        override fun invoke(result: String) {
            Log.d(TAG, "Clash Callback Received: $result")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopVpn()
            return START_NOT_STICKY
        }

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())

        val configPath = intent?.getStringExtra("config_path")
        if (configPath != null) {
             startClash(configPath)
        } else {
             Log.e(TAG, "Config path is null")
             stopSelf()
        }
        
        return START_STICKY
    }
    
    private fun startClash(configPath: String) {
        if (isRunning) return
        
        val homeDir = File(configPath).parentFile
        val configContent = File(configPath).readText()

        Log.e(TAG, "Initializing Clash Core (JNA Adapted)...")

        try {
            if (!establishVpn()) {
                Log.e(TAG, "Failed to establish VPN")
                stopSelf()
                return
            }

            val initJson = JSONObject()
            initJson.put("id", "init")
            initJson.put("method", "initClash")
            initJson.put("data", homeDir.absolutePath)
            
            Log.e(TAG, "Invoking initClash...")
            // Pass the JNA Callback interface, which JNA converts to a C function pointer
            INSTANCE.invokeAction(clashCallback, initJson.toString())
            Log.e(TAG, "Init Sent.")

            val configJson = JSONObject()
            configJson.put("id", "config")
            configJson.put("method", "updateConfig")
            configJson.put("data", configContent)
            
            Log.e(TAG, "Invoking updateConfig...")
            INSTANCE.invokeAction(clashCallback, configJson.toString())
            Log.e(TAG, "Config Update Sent.")

            val fd = tunFd!!.fd
            Log.e(TAG, "Starting TUN with FD: $fd")
            
            // For now pass null callback to startTUN as our simplified lib.go ignores it
            val result = INSTANCE.startTUN(null, fd, "gvisor", "172.19.0.1/30", "8.8.8.8")
            
            if (result) {
                Log.e(TAG, "Clash Native TUN Started Successfully!")
                isRunning = true
            } else {
                Log.e(TAG, "Clash Native TUN Start FAILED.")
                stopVpn()
            }

        } catch (e: Exception) {
            Log.e(TAG, "Native Error: ${e.message}", e)
            stopVpn()
        }
    }

    private fun establishVpn(): Boolean {
        return try {
            val builder = Builder()
            builder.setMtu(1500)
            builder.addAddress("172.19.0.1", 30) // Virtual IP
            builder.addRoute("0.0.0.0", 0)       // Route all traffic
            builder.addDnsServer("8.8.8.8")
            builder.setSession("Clash VPN")

            val pendingIntent = PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE
            )
            builder.setConfigureIntent(pendingIntent)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            
            tunFd = builder.establish()
            tunFd != null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish VPN", e)
            false
        }
    }

    private fun stopVpn() {
        isRunning = false
        try {
            INSTANCE.stopTun()
            tunFd?.close()
            tunFd = null
            stopForeground(true)
            stopSelf()
            Log.d(TAG, "VPN Stopped")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Clash VPN Service",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Clash VPN")
            .setContentText("Service is running")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}
