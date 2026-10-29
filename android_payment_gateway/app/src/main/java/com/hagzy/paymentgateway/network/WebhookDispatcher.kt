package com.hagzy.paymentgateway.network

import android.util.Log
import com.hagzy.paymentgateway.BuildConfig
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
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    /**
     * Computes HMAC-SHA256 hex signature for payload
     */
    fun computeHmacSha256(payload: String, secret: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        val secretKey = SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256")
        mac.init(secretKey)
        val hmacBytes = mac.doFinal(payload.toByteArray(StandardCharsets.UTF_8))
        return hmacBytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Dispatches payment event to Cloud Function webhook with HMAC signature
     */
    suspend fun dispatchEvent(event: PaymentEvent): Result<String> = withContext(Dispatchers.IO) {
        val payload = event.toJsonString()
        val signature = computeHmacSha256(payload, BuildConfig.WEBHOOK_SECRET)

        val request = Request.Builder()
            .url(BuildConfig.WEBHOOK_URL)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Webhook-Signature", signature)
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        try {
            val response = client.newCall(request).execute()
            val responseBody = response.body?.string().orEmpty()

            if (response.isSuccessful) {
                Log.d(TAG, "Event ${event.eventId} dispatched successfully: $responseBody")
                Result.success(responseBody)
            } else {
                val errorMsg = "HTTP ${response.code}: $responseBody"
                Log.e(TAG, "Failed dispatching event ${event.eventId}: $errorMsg")
                Result.failure(Exception(errorMsg))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Network exception dispatching event ${event.eventId}", e)
            Result.failure(e)
        }
    }
}

