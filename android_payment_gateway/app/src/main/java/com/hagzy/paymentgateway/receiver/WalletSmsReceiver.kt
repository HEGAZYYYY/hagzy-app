package com.hagzy.paymentgateway.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
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

class WalletSmsReceiver : BroadcastReceiver() {

    private val receiverScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val sender = messages[0].displayOriginatingAddress.orEmpty()
        val fullBody = messages.joinToString("") { it.displayMessageBody.orEmpty() }
        val timestamp = messages[0].timestampMillis

        Log.d(TAG, "Incoming SMS from [$sender]: $fullBody")

        // Check if sender or content belongs to Egyptian mobile wallets
        val isWalletSender = WALLET_SENDERS.any { sender.contains(it, ignoreCase = true) } ||
                fullBody.contains("فودافون كاش", ignoreCase = true) ||
                fullBody.contains("أورنج كاش", ignoreCase = true) ||
                fullBody.contains("اتصالات كاش", ignoreCase = true) ||
                fullBody.contains("WE Pay", ignoreCase = true)

        if (!isWalletSender) {
            Log.d(TAG, "SMS ignored: Not a recognized wallet sender.")
            return
        }

        parseWalletSms(context, fullBody, timestamp)
    }

    fun parseWalletSms(context: Context, fullBody: String, timestamp: Long) {
        val arPattern = Pattern.compile(
            """(?:تم استلام مبلغ|تم إيداع|استلمت|تم تحويل)\s*([\d,]+(?:\.\d{1,2})?)\s*(?:جنيه|ج\.م|EGP).*?(?:من رقم|من|رقم)\s*(?:\+?2)?(01[0125]\d{8})""",
            Pattern.CASE_INSENSITIVE
        )

        val enPattern = Pattern.compile(
            """(?:received|transferred|deposited)\s*([\d,]+(?:\.\d{1,2})?)\s*(?:EGP|LE|ج\.م)?.*?(?:from)\s*(?:\+?2)?(01[0125]\d{8})""",
            Pattern.CASE_INSENSITIVE
        )

        val refPattern = Pattern.compile(
            """(?:رقم العملية|Transaction ID|Ref|Ref ID)[:\s#]*([A-Za-z0-9]+)""",
            Pattern.CASE_INSENSITIVE
        )

        var amount: Double? = null
        var senderPhone: String? = null

        val arMatcher = arPattern.matcher(fullBody)
        if (arMatcher.find()) {
            amount = arMatcher.group(1)?.replace(",", "")?.toDoubleOrNull()
            senderPhone = arMatcher.group(2)
        } else {
            val enMatcher = enPattern.matcher(fullBody)
            if (enMatcher.find()) {
                amount = enMatcher.group(1)?.replace(",", "")?.toDoubleOrNull()
                senderPhone = enMatcher.group(2)
            }
        }

        var providerRef: String? = null
        val refMatcher = refPattern.matcher(fullBody)
        if (refMatcher.find()) {
            providerRef = refMatcher.group(1)
        }

        if (amount != null && senderPhone != null) {
            val normalizedPhone = senderPhone.trim()

            // Deterministic event ID
            val eventId = if (!providerRef.isNullOrBlank()) {
                "mw_ref_${providerRef.trim().lowercase()}"
            } else {
                val timeBucket = timestamp / 10000
                "mw_" + sha256("WALLET:$normalizedPhone:$amount:$timeBucket").take(24)
            }

            val event = PaymentEvent(
                eventId = eventId,
                paymentMethod = "MOBILE_WALLET",
                senderIdentifier = normalizedPhone,
                amount = amount,
                providerRef = providerRef,
                rawText = fullBody,
                timestamp = timestamp,
                syncStatus = SyncStatus.PENDING
            )

            processWalletEvent(context, event)
        } else {
            Log.w(TAG, "Wallet SMS did not match extraction pattern: $fullBody")
        }
    }

    private fun processWalletEvent(context: Context, event: PaymentEvent) {
        val dao = GatewayApplication.instance.database.paymentEventDao()

        receiverScope.launch {
            val insertedRow = dao.insertEvent(event)
            if (insertedRow == -1L) {
                Log.d(TAG, "Wallet event ${event.eventId} already stored.")
                return@launch
            }

            Log.i(TAG, "Captured Mobile Wallet event: ${event.senderIdentifier} -> ${event.amount} EGP (Ref: ${event.providerRef})")

            val result = WebhookDispatcher.dispatchEvent(event)
            if (result.isSuccess) {
                dao.updateSyncStatus(event.eventId, SyncStatus.SENT)
                Log.i(TAG, "Wallet event ${event.eventId} synced with backend.")
            } else {
                dao.updateSyncStatus(event.eventId, SyncStatus.FAILED, result.exceptionOrNull()?.message)
                Log.w(TAG, "Failed syncing wallet event ${event.eventId}. Scheduling retry.")
                PaymentRetryWorker.schedule(context.applicationContext)
            }
        }
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "WalletSmsReceiver"

        val WALLET_SENDERS = listOf(
            "VF-Cash",
            "VodafoneCash",
            "Vodafone",
            "OrangeCash",
            "Orange",
            "EtisalatCash",
            "e& money",
            "Etisalat",
            "WE Pay",
            "WEPay",
            "Telecom Egypt"
        )
    }
}

