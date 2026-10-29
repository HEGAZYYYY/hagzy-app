package com.hagzy.paymentgateway

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.room.Room
import com.hagzy.paymentgateway.data.local.GatewayDatabase

class GatewayApplication : Application() {

    lateinit var database: GatewayDatabase
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this

        database = Room.databaseBuilder(
            applicationContext,
            GatewayDatabase::class.java,
            "hagzy_gateway_db"
        ).fallbackToDestructiveMigration().build()

        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_SERVICE,
                "Gateway Keep-Alive Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the Hagzy payment oracle listener running in the foreground"
            }

            val alertChannel = NotificationChannel(
                CHANNEL_PAYMENTS,
                "Payment Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts for incoming InstaPay and Mobile Wallet payments"
            }

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(serviceChannel)
            manager.createNotificationChannel(alertChannel)
        }
    }

    companion object {
        const val CHANNEL_SERVICE = "hagzy_gateway_keep_alive"
        const val CHANNEL_PAYMENTS = "hagzy_gateway_payments"

        lateinit var instance: GatewayApplication
            private set
    }
}

