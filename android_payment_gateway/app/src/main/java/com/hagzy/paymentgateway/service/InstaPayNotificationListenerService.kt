package com.hagzy.paymentgateway.service

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus
import com.hagzy.paymentgateway.network.WebhookDispatcher
import com.hagzy.paymentgateway.worker.PaymentRetryWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.util.regex.Pattern

class InstaPayNotificationListenerService : NotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val dao = GatewayApplication.instance.database.paymentEventDao()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName
        // Process official InstaPay app notifications and debug test notifications
        if (packageName != INSTAPAY_PACKAGE && !packageName.contains("test") && packageName != applicationContext.packageName) {
            return
        }

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()

        val fullContent = "$title\n$text\n$bigText".trim()
        Log.d(TAG, "InstaPay candidate notification: $fullContent")

        parseInstaPayContent(fullContent, sbn.postTime)
    }

    fun parseInstaPayContent(rawText: String, notificationTime: Long) {
        // Regex patterns for English and Arabic InstaPay receipt notifications
        val enPattern = Pattern.compile(
            """(?:You have received|Received)\s+([\d,]+(?:\.\d{1,2})?)\s*(?:EGP|LE|ج\.م)?\s+from\s+([a-zA-Z0-9_.-]+(?:@instapay)?)""",
            Pattern.CASE_INSENSITIVE
        )

        val arPattern = Pattern.compile(
            """(?:تم استلام مبلغ|تم تحويل مبلغ|استلمت)\s*([\d,]+(?:\.\d{1,2})?)\s*(?:ج\.م|جنيه|EGP)?\s*(?:من)\s*([a-zA-Z0-9_.-]+(?:@instapay)?)""",
            Pattern.CASE_INSENSITIVE
        )

        var amount: Double? = null
        var senderIpa: String? = null

        val enMatcher = enPattern.matcher(rawText)
        if (enMatcher.find()) {
            val amountStr = enMatcher.group(1)?.replace(",", "")
            amount = amountStr?.toDoubleOrNull()
            senderIpa = enMatcher.group(2)
        } else {
            val arMatcher = arPattern.matcher(rawText)
            if (arMatcher.find()) {
                val amountStr = arMatcher.group(1)?.replace(",", "")
                amount = amountStr?.toDoubleOrNull()
                senderIpa = arMatcher.group(2)
            }
        }

        if (amount != null && senderIpa != null) {
            // Normalize IPA
            var normalizedIpa = senderIpa.trim().lowercase()
            if (!normalizedIpa.endsWith("@instapay")) {
                normalizedIpa = "$normalizedIpa@instapay"
            }

            // Generate deterministic eventId using SHA-256 of IPA + amount + timestamp bucket (10-sec precision)
            val timeBucket = notificationTime / 10000
            val hashInput = "INSTAPAY:$normalizedIpa:$amount:$timeBucket"
            val eventId = "ip_" + sha256(hashInput).take(24)

            val event = PaymentEvent(
                eventId = eventId,
                paymentMethod = "INSTAPAY",
                senderIdentifier = normalizedIpa,
                amount = amount,
                providerRef = null,
                rawText = rawText,
                timestamp = notificationTime,
                syncStatus = SyncStatus.PENDING
            )

            processPaymentEvent(event)
        } else {
            Log.d(TAG, "Notification content did not match InstaPay receipt structure: $rawText")
        }
    }

    private fun processPaymentEvent(event: PaymentEvent) {
        serviceScope.launch {
            val insertedRow = dao.insertEvent(event)
            if (insertedRow == -1L) {
                Log.d(TAG, "Event ${event.eventId} was already recorded.")
                return@launch
            }

            Log.i(TAG, "Captured InstaPay event: ${event.senderIdentifier} -> ${event.amount} EGP")

            // Immediate dispatch attempt
            val result = WebhookDispatcher.dispatchEvent(event)
            if (result.isSuccess) {
                dao.updateSyncStatus(event.eventId, SyncStatus.SENT)
                Log.i(TAG, "InstaPay event ${event.eventId} successfully synced with backend.")
            } else {
                dao.updateSyncStatus(event.eventId, SyncStatus.FAILED, result.exceptionOrNull()?.message)
                Log.w(TAG, "Failed syncing event ${event.eventId}. Queuing WorkManager retry.")
                PaymentRetryWorker.schedule(applicationContext)
            }
        }
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "InstaPayListener"
        const val INSTAPAY_PACKAGE = "com.egyptianbanks.instapay"
    }
}

