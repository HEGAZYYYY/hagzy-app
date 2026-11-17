package com.hagzy.paymentgateway.service

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.network.PaymentEventPipeline
import com.hagzy.paymentgateway.receiver.WalletSmsReceiver
import com.hagzy.paymentgateway.util.PaymentTextParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class InstaPayNotificationListenerService : NotificationListenerService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName.orEmpty()
        val isOfficialInstaPay = INSTAPAY_PACKAGES.contains(packageName)
        val isTestPackage = packageName.contains("test", ignoreCase = true) ||
            packageName == applicationContext.packageName
        val isSmsApp = SMS_APP_PACKAGES.contains(packageName)

        if (!isOfficialInstaPay && !isTestPackage && !isSmsApp) {
            return
        }

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty().trim()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty().trim()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty().trim()

        val fullContent = listOf(title, text, bigText)
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString("\n")
        if (fullContent.isEmpty()) return

        if (isSmsApp) {
            if (!WalletSmsReceiver.isWalletSenderOrContent(title, fullContent)) {
                return
            }
            Log.d(TAG, "Wallet SMS notification candidate [$packageName]: $fullContent")
            val smsEvent = PaymentTextParser.parseWalletSms(fullContent, sbn.postTime)
            if (smsEvent != null) {
                dispatchEvent(smsEvent)
            }
            return
        }

        Log.d(TAG, "InstaPay candidate notification [$packageName]: $fullContent")
        parseInstaPayContent(fullContent, sbn.postTime, isOfficialInstaPayApp = isOfficialInstaPay)
    }

    fun parseInstaPayContent(
        rawText: String,
        notificationTime: Long,
        isOfficialInstaPayApp: Boolean = false
    ) {
        val event = PaymentTextParser.parseInstaPayNotification(
            rawText = rawText,
            timestamp = notificationTime,
            isOfficialInstaPayApp = isOfficialInstaPayApp
        )
        if (event != null) {
            dispatchEvent(event)
        } else {
            Log.d(TAG, "Notification content did not match InstaPay receipt structure: $rawText")
        }
    }

    private fun dispatchEvent(event: PaymentEvent) {
        val ctx = GatewayApplication.instance
        serviceScope.launch {
            PaymentEventPipeline.recordAndDispatch(ctx, event)
        }
    }

    companion object {
        private const val TAG = "InstaPayListener"

        val INSTAPAY_PACKAGES = setOf(
            "com.emeint.android.mysrv",
            "com.egyptianbanks.instapay",
            "eg.com.ebc.instapay"
        )

        val SMS_APP_PACKAGES = setOf(
            "com.google.android.apps.messaging",
            "com.samsung.android.messaging",
            "com.android.mms",
            "com.miui.mms",
            "com.oneplus.mms",
            "com.coloros.mms",
            "com.huawei.message"
        )
    }
}

