package com.hagzy.paymentgateway.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus

class Converters {
    @TypeConverter
    fun fromSyncStatus(value: SyncStatus): String = value.name

    @TypeConverter
    fun toSyncStatus(value: String): SyncStatus = SyncStatus.valueOf(value)
}

@Database(entities = [PaymentEvent::class], version = 1, exportSchema = false)
@TypeConverters(Converters::class)
abstract class GatewayDatabase : RoomDatabase() {
    abstract fun paymentEventDao(): PaymentEventDao
}

