package com.hagzy.paymentgateway.data.model

import androidx.room.Entity
import androidx.room.PrimaryKey
import org.json.JSONObject

enum class SyncStatus {
    PENDING,
    SENT,
    FAILED
}

@Entity(tableName = "payment_events")
data class PaymentEvent(
    @PrimaryKey
    val eventId: String,
    val paymentMethod: String, // "INSTAPAY" | "MOBILE_WALLET"
    val senderIdentifier: String, // e.g., "username@instapay" or "01012345678"
    val amount: Double,
    val providerRef: String?,
    val rawText: String,
    val timestamp: Long = System.currentTimeMillis(),
    val syncStatus: SyncStatus = SyncStatus.PENDING,
    val retryCount: Int = 0,
    val errorMessage: String? = null
) {
    fun toJsonString(): String {
        val json = JSONObject()
        json.put("eventId", eventId)
        json.put("paymentMethod", paymentMethod)
        json.put("senderIdentifier", senderIdentifier)
        json.put("amount", amount)
        json.put("providerRef", providerRef ?: JSONObject.NULL)
        json.put("rawText", rawText)
        json.put("timestamp", timestamp)
        return json.toString()
    }
}

