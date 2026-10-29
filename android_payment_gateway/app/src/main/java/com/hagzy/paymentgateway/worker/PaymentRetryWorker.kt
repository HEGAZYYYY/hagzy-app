package com.hagzy.paymentgateway.worker

import android.content.Context
import android.util.Log
import androidx.work.*
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.model.SyncStatus
import com.hagzy.paymentgateway.network.WebhookDispatcher
import java.util.concurrent.TimeUnit

class PaymentRetryWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    private val dao = GatewayApplication.instance.database.paymentEventDao()

    override suspend fun doWork(): Result {
        Log.d(TAG, "Executing PaymentRetryWorker...")
        val pendingEvents = dao.getEventsByStatus(SyncStatus.PENDING) +
                dao.getEventsByStatus(SyncStatus.FAILED)

        if (pendingEvents.isEmpty()) {
            Log.d(TAG, "No pending payment events to retry.")
            return Result.success()
        }

        var anyFailed = false

        for (event in pendingEvents) {
            dao.incrementRetryCount(event.eventId)
            val result = WebhookDispatcher.dispatchEvent(event)

            if (result.isSuccess) {
                dao.updateSyncStatus(event.eventId, SyncStatus.SENT, null)
                Log.d(TAG, "Successfully retried event ${event.eventId}")
            } else {
                val error = result.exceptionOrNull()?.message ?: "Unknown error"
                dao.updateSyncStatus(event.eventId, SyncStatus.FAILED, error)
                anyFailed = true
                Log.e(TAG, "Failed retry for event ${event.eventId}: $error")
            }
        }

        return if (anyFailed) Result.retry() else Result.success()
    }

    companion object {
        private const val TAG = "PaymentRetryWorker"
        const val UNIQUE_WORK_NAME = "hagzy_payment_retry_work"

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = OneTimeWorkRequestBuilder<PaymentRetryWorker>()
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    15,
                    TimeUnit.SECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                UNIQUE_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}

