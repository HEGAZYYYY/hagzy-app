package com.hagzy.paymentgateway.data.local

import androidx.lifecycle.LiveData
import androidx.room.*
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus

@Dao
interface PaymentEventDao {

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertEvent(event: PaymentEvent): Long

    @Query("SELECT * FROM payment_events WHERE syncStatus = :status ORDER BY timestamp ASC")
    suspend fun getEventsByStatus(status: SyncStatus): List<PaymentEvent>

    @Query("SELECT * FROM payment_events WHERE eventId = :id LIMIT 1")
    suspend fun getEventById(id: String): PaymentEvent?

    @Query("UPDATE payment_events SET syncStatus = :status, errorMessage = :error WHERE eventId = :id")
    suspend fun updateSyncStatus(id: String, status: SyncStatus, error: String? = null)

    @Query("UPDATE payment_events SET retryCount = retryCount + 1 WHERE eventId = :id")
    suspend fun incrementRetryCount(id: String)

    @Query("SELECT * FROM payment_events ORDER BY timestamp DESC LIMIT 100")
    fun getAllEventsLiveData(): LiveData<List<PaymentEvent>>

    @Query("SELECT COUNT(*) FROM payment_events WHERE syncStatus = 'PENDING' OR syncStatus = 'FAILED'")
    fun getPendingCountLiveData(): LiveData<Int>
}

