package com.hagzy.paymentgateway.network

import android.util.Log
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.local.GatewayConfig
import com.hagzy.paymentgateway.data.model.PaymentEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object WebhookDispatcher {
    private const val TAG = "WebhookDispatcher"
    private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    /**
     * Computes HMAC-SHA256 hex signature for payload.
     */
    fun computeHmacSha256(payload: String, secret: String): String {
        require(secret.isNotBlank()) { "Webhook secret must not be blank" }
        val mac = Mac.getInstance("HmacSHA256")
        val secretKey = SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256")
        mac.init(secretKey)
        val hmacBytes = mac.doFinal(payload.toByteArray(StandardCharsets.UTF_8))
        return hmacBytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Dispatches payment event to configured Hagzy listener/webhook endpoint with HMAC & key headers.
     */
    suspend fun dispatchEvent(event: PaymentEvent): Result<String> = withContext(Dispatchers.IO) {
        val config = GatewayConfig(GatewayApplication.instance)
        val url = config.webhookUrl.trim()
        val secret = config.webhookSecret.trim()

        if (url.isEmpty()) {
            return@withContext Result.failure(IllegalStateException("Webhook URL is not configured"))
        }
        if (secret.isEmpty()) {
            return@withContext Result.failure(
                IllegalStateException("Webhook secret is not configured. Save PAYMENT_LISTENER_KEY in settings.")
            )
        }

        val payload = event.toJsonString()
        val timestampStr = System.currentTimeMillis().toString()
        val hmacWithTimestamp = computeHmacSha256("$payload.$timestampStr", secret)
        val hmacPayloadOnly = computeHmacSha256(payload, secret)

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Timestamp", timestampStr)
            .addHeader("X-Signature", hmacWithTimestamp)
            .addHeader("X-Hagzy-Signature", hmacWithTimestamp)
            .addHeader("X-Webhook-Signature", hmacPayloadOnly)
            .addHeader("X-Listener-Key", secret)
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        try {
            client.newCall(request).execute().use { response ->
                val responseBody = response.body?.string().orEmpty()
                if (response.isSuccessful) {
                    Log.d(TAG, "Event ${event.eventId} dispatched successfully: $responseBody")
                    Result.success(responseBody)
                } else {
                    val errorMsg = "HTTP ${response.code}: $responseBody"
                    Log.e(TAG, "Failed dispatching event ${event.eventId}: $errorMsg")
                    Result.failure(Exception(errorMsg))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Network exception dispatching event ${event.eventId}", e)
            Result.failure(e)
        }
    }

    /**
     * Sends a gateway liveness heartbeat to /api/payments/listener/heartbeat.
     */
    suspend fun sendHeartbeat(): Result<String> = withContext(Dispatchers.IO) {
        val config = GatewayConfig(GatewayApplication.instance)
        val heartbeatUrl = config.getHeartbeatUrl()
        val secret = config.webhookSecret.trim()

        if (secret.isEmpty()) {
            val err = "Missing secret key"
            config.lastHeartbeatStatus = "Error: $err"
            return@withContext Result.failure(IllegalStateException(err))
        }

        val payload = """{"source":"hagzy_android_gateway"}"""
        val timestampStr = System.currentTimeMillis().toString()
        val hmacWithTimestamp = computeHmacSha256("$payload.$timestampStr", secret)

        val request = Request.Builder()
            .url(heartbeatUrl)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Timestamp", timestampStr)
            .addHeader("X-Signature", hmacWithTimestamp)
            .addHeader("X-Hagzy-Signature", hmacWithTimestamp)
            .addHeader("X-Listener-Key", secret)
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        try {
            client.newCall(request).execute().use { response ->
                val responseBody = response.body?.string().orEmpty()
                if (response.isSuccessful) {
                    config.lastHeartbeatAt = System.currentTimeMillis()
                    config.lastHeartbeatStatus = "Online (HTTP ${response.code})"
                    Log.d(TAG, "Heartbeat OK: $heartbeatUrl")
                    Result.success(responseBody)
                } else {
                    val msg = "HTTP ${response.code}"
                    config.lastHeartbeatStatus = "Failed ($msg)"
                    Log.w(TAG, "Heartbeat failed ($msg): $responseBody")
                    Result.failure(Exception("$msg: $responseBody"))
                }
            }
        } catch (e: Exception) {
            config.lastHeartbeatStatus = "Error: ${e.message ?: "Network unreachable"}"
            Log.e(TAG, "Heartbeat exception", e)
            Result.failure(e)
        }
    }
}

