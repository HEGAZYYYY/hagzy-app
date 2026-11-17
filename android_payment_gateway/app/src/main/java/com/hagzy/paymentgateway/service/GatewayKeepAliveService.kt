package com.hagzy.paymentgateway.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.model.SyncStatus
import com.hagzy.paymentgateway.network.WebhookDispatcher
import com.hagzy.paymentgateway.ui.MainActivity
import com.hagzy.paymentgateway.worker.PaymentRetryWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class GatewayKeepAliveService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var heartbeatJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock()
        startHeartbeatLoop()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        startHeartbeatLoop()
        return START_STICKY
    }

    override fun onDestroy() {
        heartbeatJob?.cancel()
        serviceScope.cancel()
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startHeartbeatLoop() {
        if (heartbeatJob?.isActive == true) return
        heartbeatJob = serviceScope.launch {
            while (isActive) {
                try {
                    WebhookDispatcher.sendHeartbeat()
                    val dao = GatewayApplication.instance.database.paymentEventDao()
                    val pending = dao.getEventsByStatus(SyncStatus.PENDING) +
                        dao.getEventsByStatus(SyncStatus.FAILED)
                    if (pending.isNotEmpty()) {
                        PaymentRetryWorker.schedule(applicationContext)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Keep-alive heartbeat loop warning: ${e.message}")
                }
                delay(HEARTBEAT_INTERVAL_MS)
            }
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "HagzyGateway::KeepAliveWakeLock"
        ).apply {
            setReferenceCounted(false)
            acquire(24 * 60 * 60 * 1000L) // 24 hours failsafe
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, GatewayApplication.CHANNEL_SERVICE)
            .setContentTitle("Hagzy Payment Oracle Active")
            .setContentText("Listening for InstaPay and Vodafone Cash transfers...")
            .setSmallIcon(android.R.drawable.ic_menu_agenda)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val TAG = "GatewayKeepAlive"
        private const val NOTIFICATION_ID = 1001
        private const val HEARTBEAT_INTERVAL_MS = 2 * 60 * 1000L

        fun start(context: Context) {
            val intent = Intent(context, GatewayKeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, GatewayKeepAliveService::class.java)
            context.stopService(intent)
        }
    }
}

