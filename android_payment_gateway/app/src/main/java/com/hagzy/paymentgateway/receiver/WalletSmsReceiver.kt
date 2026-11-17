package com.hagzy.paymentgateway.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import com.hagzy.paymentgateway.network.PaymentEventPipeline
import com.hagzy.paymentgateway.util.PaymentTextParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

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

        if (!isWalletSenderOrContent(sender, fullBody)) {
            Log.d(TAG, "SMS ignored: Not a recognized wallet sender.")
            return
        }

        val event = PaymentTextParser.parseWalletSms(fullBody, timestamp)
        if (event == null) {
            Log.w(TAG, "Wallet SMS did not match extraction pattern: $fullBody")
            return
        }

        val pendingResult = goAsync()
        receiverScope.launch {
            try {
                PaymentEventPipeline.recordAndDispatch(context.applicationContext, event)
            } finally {
                pendingResult.finish()
            }
        }
    }

    fun parseWalletSms(context: Context, fullBody: String, timestamp: Long) {
        val event = PaymentTextParser.parseWalletSms(fullBody, timestamp)
        if (event != null) {
            receiverScope.launch {
                PaymentEventPipeline.recordAndDispatch(context.applicationContext, event)
            }
        } else {
            Log.w(TAG, "Wallet SMS did not match extraction pattern: $fullBody")
        }
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

        fun isWalletSenderOrContent(sender: String, body: String): Boolean {
            return WALLET_SENDERS.any { sender.contains(it, ignoreCase = true) } ||
                body.contains("فودافون كاش", ignoreCase = true) ||
                body.contains("أورنج كاش", ignoreCase = true) ||
                body.contains("اتصالات كاش", ignoreCase = true) ||
                body.contains("WE Pay", ignoreCase = true) ||
                body.contains("vfcash", ignoreCase = true) ||
                body.contains("VF-Cash", ignoreCase = true)
        }
    }
}

