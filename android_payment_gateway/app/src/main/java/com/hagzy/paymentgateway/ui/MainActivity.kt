package com.hagzy.paymentgateway.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.R
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus
import com.hagzy.paymentgateway.databinding.ActivityMainBinding
import com.hagzy.paymentgateway.databinding.ItemEventLogBinding
import com.hagzy.paymentgateway.receiver.WalletSmsReceiver
import com.hagzy.paymentgateway.service.GatewayKeepAliveService
import com.hagzy.paymentgateway.service.InstaPayNotificationListenerService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val adapter = EventLogAdapter()

    private val requestSmsPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions[Manifest.permission.RECEIVE_SMS] == true
        if (granted) {
            Toast.makeText(this, "SMS permissions granted!", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "SMS permission denied.", Toast.LENGTH_SHORT).show()
        }
        updatePermissionButtons()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)

        setupRecyclerView()
        setupListeners()
        observeDatabase()

        // Ensure keep-alive service is running
        GatewayKeepAliveService.start(this)
    }

    override fun onResume() {
        super.onResume()
        updatePermissionButtons()
    }

    private fun setupRecyclerView() {
        binding.rvEvents.layoutManager = LinearLayoutManager(this)
        binding.rvEvents.adapter = adapter
    }

    private fun setupListeners() {
        binding.btnToggleService.setOnClickListener {
            GatewayKeepAliveService.stop(this)
            GatewayKeepAliveService.start(this)
            Toast.makeText(this, "Gateway Keep-Alive Service Restarted", Toast.LENGTH_SHORT).show()
        }

        binding.btnGrantSms.setOnClickListener {
            requestSmsPermissionLauncher.launch(
                arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
            )
        }

        binding.btnGrantNotification.setOnClickListener {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            startActivity(intent)
        }

        binding.btnGrantBattery.setOnClickListener {
            requestIgnoreBatteryOptimization()
        }

        // Test simulator buttons
        binding.btnSimulateInstapay.setOnClickListener {
            simulateInstaPayReceipt()
        }

        binding.btnSimulateVodafone.setOnClickListener {
            simulateVodafoneCashSms()
        }
    }

    private fun observeDatabase() {
        val dao = GatewayApplication.instance.database.paymentEventDao()

        dao.getAllEventsLiveData().observe(this) { events ->
            adapter.submitList(events)
            binding.tvEmptyEvents.visibility = if (events.isEmpty()) View.VISIBLE else View.GONE
        }

        dao.getPendingCountLiveData().observe(this) { pendingCount ->
            binding.tvPendingCount.text = "Offline queue: $pendingCount pending retry"
        }
    }

    private fun updatePermissionButtons() {
        // SMS permission check
        val smsGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED
        binding.btnGrantSms.text = if (smsGranted) "SMS Granted ✓" else "Grant SMS Access"
        binding.btnGrantSms.isEnabled = !smsGranted

        // Notification Listener check
        val notifGranted = isNotificationServiceEnabled()
        binding.btnGrantNotification.text = if (notifGranted) "Notif Listener Active ✓" else "Enable Notif Listener"
        binding.btnGrantNotification.isEnabled = !notifGranted

        // Battery optimization exemption check
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val batteryIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
        binding.btnGrantBattery.text = if (batteryIgnored) "Battery Optimized: Exempt ✓" else "Exempt from Battery Saver"
        binding.btnGrantBattery.isEnabled = !batteryIgnored
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat?.contains(pkgName) == true
    }

    private fun requestIgnoreBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        }
    }

    private fun simulateInstaPayReceipt() {
        val fakeNotification = "You have received 150.00 EGP from abdelhamed1978@instapay"
        val service = InstaPayNotificationListenerService()
        // Inject application context for database lookup
        service.parseInstaPayContent(fakeNotification, System.currentTimeMillis())
        Toast.makeText(this, "Simulated InstaPay receipt triggered!", Toast.LENGTH_SHORT).show()
    }

    private fun simulateVodafoneCashSms() {
        val fakeSms = "تم استلام مبلغ 200 جنيه من 01012345678 رقم العملية VF984128"
        val receiver = WalletSmsReceiver()
        receiver.parseWalletSms(this, fakeSms, System.currentTimeMillis())
        Toast.makeText(this, "Simulated Vodafone Cash SMS triggered!", Toast.LENGTH_SHORT).show()
    }
}

class EventLogAdapter : RecyclerView.Adapter<EventLogAdapter.ViewHolder>() {

    private var items = listOf<PaymentEvent>()
    private val dateFormat = SimpleDateFormat("HH:mm:ss dd/MM", Locale.US)

    fun submitList(newItems: List<PaymentEvent>) {
        items = newItems
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemEventLogBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    inner class ViewHolder(private val binding: ItemEventLogBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(event: PaymentEvent) {
            binding.tvMethodBadge.text = event.paymentMethod
            binding.tvAmount.text = "${"%.2f".format(event.amount)} EGP"
            binding.tvSender.text = "From: ${event.senderIdentifier}"

            val refText = if (event.providerRef != null) "Ref: ${event.providerRef}" else "Event: ${event.eventId.take(12)}..."
            val timeText = dateFormat.format(Date(event.timestamp))
            binding.tvRefAndDate.text = "$refText • $timeText"

            binding.tvSyncStatus.text = event.syncStatus.name
            when (event.syncStatus) {
                SyncStatus.SENT -> binding.tvSyncStatus.setTextColor(0xFF10B981.toInt())
                SyncStatus.PENDING -> binding.tvSyncStatus.setTextColor(0xFFF59E0B.toInt())
                SyncStatus.FAILED -> binding.tvSyncStatus.setTextColor(0xFFEF4444.toInt())
            }
        }
    }
}

