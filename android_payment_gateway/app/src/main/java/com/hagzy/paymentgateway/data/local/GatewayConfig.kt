package com.hagzy.paymentgateway.data.local

import android.content.Context
import com.hagzy.paymentgateway.BuildConfig

class GatewayConfig(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )

    var webhookUrl: String
        get() {
            val saved = prefs.getString(KEY_WEBHOOK_URL, null)?.trim()
            if (!saved.isNullOrEmpty()) return saved
            val buildDefault = BuildConfig.WEBHOOK_URL.trim()
            return if (buildDefault.isNotEmpty()) buildDefault else DEFAULT_WEBHOOK_URL
        }
        set(value) {
            prefs.edit().putString(KEY_WEBHOOK_URL, value.trim()).apply()
        }

    var webhookSecret: String
        get() {
            val saved = prefs.getString(KEY_WEBHOOK_SECRET, null)?.trim()
            if (!saved.isNullOrEmpty()) return saved
            return BuildConfig.WEBHOOK_SECRET.trim()
        }
        set(value) {
            prefs.edit().putString(KEY_WEBHOOK_SECRET, value.trim()).apply()
        }

    var lastHeartbeatAt: Long
        get() = prefs.getLong(KEY_LAST_HEARTBEAT_AT, 0L)
        set(value) {
            prefs.edit().putLong(KEY_LAST_HEARTBEAT_AT, value).apply()
        }

    var lastHeartbeatStatus: String
        get() = prefs.getString(KEY_LAST_HEARTBEAT_STATUS, null) ?: DEFAULT_HEARTBEAT_STATUS
        set(value) {
            prefs.edit().putString(KEY_LAST_HEARTBEAT_STATUS, value).apply()
        }

    fun getHeartbeatUrl(): String = getHeartbeatUrl(webhookUrl)

    companion object {
        private const val PREFS_NAME = "hagzy_gateway_prefs"
        private const val KEY_WEBHOOK_URL = "webhook_url"
        private const val KEY_WEBHOOK_SECRET = "webhook_secret"
        private const val KEY_LAST_HEARTBEAT_AT = "last_heartbeat_at"
        private const val KEY_LAST_HEARTBEAT_STATUS = "last_heartbeat_status"

        const val DEFAULT_WEBHOOK_URL = "https://qgimngblsrfgzavuxpde.supabase.co/functions/v1/hagzy-api/api/payments/listener"
        const val DEFAULT_HEARTBEAT_STATUS = "Never connected"

        fun getHeartbeatUrl(webhookUrl: String): String {
            val cleaned = webhookUrl.trim().trimEnd('/')
            val baseInput = if (cleaned.isEmpty()) DEFAULT_WEBHOOK_URL else cleaned
            val withoutQuery = baseInput.substringBefore('?')

            val apiPaymentsIdx = withoutQuery.indexOf("/api/payments")
            if (apiPaymentsIdx >= 0) {
                return withoutQuery.substring(0, apiPaymentsIdx) + "/api/payments/listener/heartbeat"
            }

            if (withoutQuery.endsWith("/api")) {
                return "$withoutQuery/payments/listener/heartbeat"
            }

            return "$withoutQuery/api/payments/listener/heartbeat"
        }
    }
}

