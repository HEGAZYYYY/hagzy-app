package com.hagzy.paymentgateway.network

import android.content.Context
import android.util.Log
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus
import com.hagzy.paymentgateway.worker.PaymentRetryWorker

object PaymentEventPipeline {
    private const val TAG = "PaymentEventPipeline"

    /**
     * Persists the event in Room DB (deduplicating via PrimaryKey IGNORE) and dispatches it immediately.
     * Returns true if newly recorded, false if already recorded earlier.
     */
    suspend fun recordAndDispatch(context: Context, event: PaymentEvent): Boolean {
        val dao = GatewayApplication.instance.database.paymentEventDao()
        val insertedRow = dao.insertEvent(event)
        if (insertedRow == -1L) {
            Log.d(TAG, "Event ${event.eventId} already recorded (deduplicated).")
            return false
        }

        Log.i(TAG, "Captured ${event.paymentMethod} event: ${event.senderIdentifier} -> ${event.amount} EGP")
        val result = WebhookDispatcher.dispatchEvent(event)
        if (result.isSuccess) {
            dao.updateSyncStatus(event.eventId, SyncStatus.SENT, null)
            Log.i(TAG, "Event ${event.eventId} synced successfully with backend.")
        } else {
            val err = result.exceptionOrNull()?.message
            dao.updateSyncStatus(event.eventId, SyncStatus.FAILED, err)
            Log.w(TAG, "Failed syncing event ${event.eventId}: $err. Queuing WorkManager retry.")
            PaymentRetryWorker.schedule(context.applicationContext)
        }
        return true
    }
}
