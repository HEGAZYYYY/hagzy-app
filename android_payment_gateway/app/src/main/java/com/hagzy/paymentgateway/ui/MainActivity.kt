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
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.hagzy.paymentgateway.GatewayApplication
import com.hagzy.paymentgateway.data.local.GatewayConfig
import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus
import com.hagzy.paymentgateway.databinding.ActivityMainBinding
import com.hagzy.paymentgateway.databinding.ItemEventLogBinding
import com.hagzy.paymentgateway.network.PaymentEventPipeline
import com.hagzy.paymentgateway.network.WebhookDispatcher
import com.hagzy.paymentgateway.service.GatewayKeepAliveService
import com.hagzy.paymentgateway.util.PaymentTextParser
import com.hagzy.paymentgateway.worker.PaymentRetryWorker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var gatewayConfig: GatewayConfig
    private val adapter = EventLogAdapter()
    private val heartbeatDateFormat = SimpleDateFormat("HH:mm:ss dd/MM", Locale.US)

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
        gatewayConfig = GatewayConfig(this)

        setSupportActionBar(binding.toolbar)

        setupConfigInputs()
        setupRecyclerView()
        setupListeners()
        observeDatabase()
        updateHeartbeatDisplay()

        // Ensure keep-alive service is running
        GatewayKeepAliveService.start(this)
    }

    override fun onResume() {
        super.onResume()
        updatePermissionButtons()
        updateHeartbeatDisplay()
    }

    private fun setupConfigInputs() {
        binding.etWebhookUrl.setText(gatewayConfig.webhookUrl)
        binding.etWebhookSecret.setText(gatewayConfig.webhookSecret)
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

        binding.btnSaveConfig.setOnClickListener {
            val rawUrl = binding.etWebhookUrl.text?.toString().orEmpty().trim()
            val rawSecret = binding.etWebhookSecret.text?.toString().orEmpty().trim()

            if (!rawUrl.startsWith("http://") && !rawUrl.startsWith("https://")) {
                binding.etWebhookUrl.error = "Enter a valid http:// or https:// URL"
                return@setOnClickListener
            }

            gatewayConfig.webhookUrl = rawUrl
            gatewayConfig.webhookSecret = rawSecret
            binding.etWebhookUrl.error = null
            binding.btnSaveConfig.isEnabled = false
            binding.tvHeartbeatStatus.text = "Heartbeat: Pinging server..."

            lifecycleScope.launch {
                val result = WebhookDispatcher.sendHeartbeat()
                binding.btnSaveConfig.isEnabled = true
                updateHeartbeatDisplay()
                if (result.isSuccess) {
                    Toast.makeText(
                        this@MainActivity,
                        "Saved & server heartbeat OK!",
                        Toast.LENGTH_SHORT
                    ).show()
                } else {
                    Toast.makeText(
                        this@MainActivity,
                        "Saved, ping failed: ${result.exceptionOrNull()?.message}",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }

        binding.btnRetryPending.setOnClickListener {
            PaymentRetryWorker.schedule(this)
            Toast.makeText(this, "Queued retry for pending/failed events", Toast.LENGTH_SHORT).show()
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

    private fun updateHeartbeatDisplay() {
        val status = gatewayConfig.lastHeartbeatStatus
        val lastAt = gatewayConfig.lastHeartbeatAt
        val timeText = if (lastAt > 0L) " • ${heartbeatDateFormat.format(Date(lastAt))}" else ""
        binding.tvHeartbeatStatus.text = "Heartbeat: $status$timeText"
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
        val fakeNotification = "You have recieved 150.00 EGP from mohamedra4adhegazy@instapay"
        val event = PaymentTextParser.parseInstaPayNotification(
            rawText = fakeNotification,
            timestamp = System.currentTimeMillis(),
            isOfficialInstaPayApp = true
        )
        if (event == null) {
            Toast.makeText(this, "Simulator failed to parse InstaPay sample", Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val recorded = withContext(Dispatchers.IO) {
                PaymentEventPipeline.recordAndDispatch(applicationContext, event)
            }
            val msg = if (recorded) {
                "Simulated InstaPay receipt triggered!"
            } else {
                "Duplicate simulated InstaPay event (already queued in last 10s)"
            }
            Toast.makeText(this@MainActivity, msg, Toast.LENGTH_SHORT).show()
        }
    }

    private fun simulateVodafoneCashSms() {
        val fakeRef = "VF${System.currentTimeMillis() % 1_000_000}"
        val fakeSms = "تم استلام مبلغ 100.00 جنيه من 01063330948؛\n" +
            "المسجل بإسم OMAR ISMAEL ABDELHAF\n" +
            "على رقم محفظتك 01041570557 بتاريخ 20:16 26-11-13.\n" +
            "رصيدك الحالي: 7.10 جنيه\n" +
            "رقم العملية: $fakeRef"
        val event = PaymentTextParser.parseWalletSms(fakeSms, System.currentTimeMillis())
        if (event == null) {
            Toast.makeText(this, "Simulator failed to parse VF-Cash sample", Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                PaymentEventPipeline.recordAndDispatch(applicationContext, event)
            }
            Toast.makeText(this@MainActivity, "Simulated Vodafone Cash SMS triggered!", Toast.LENGTH_SHORT).show()
        }
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
            binding.tvAmount.text = if (event.amount > 0.0) {
                "${"%.2f".format(Locale.US, event.amount)} EGP"
            } else {
                "Needs Server Parse"
            }
            binding.tvSender.text = "From: ${event.senderIdentifier}"

            val refText = if (event.providerRef != null) {
                "Ref: ${event.providerRef}"
            } else {
                "Event: ${event.eventId.take(12)}..."
            }
            val timeText = dateFormat.format(Date(event.timestamp))
            val errorSuffix = if (event.syncStatus == SyncStatus.FAILED && !event.errorMessage.isNullOrBlank()) {
                " • ${event.errorMessage}"
            } else {
                ""
            }
            binding.tvRefAndDate.text = "$refText • $timeText$errorSuffix"

            binding.tvSyncStatus.text = event.syncStatus.name
            when (event.syncStatus) {
                SyncStatus.SENT -> binding.tvSyncStatus.setTextColor(0xFF10B981.toInt())
                SyncStatus.PENDING -> binding.tvSyncStatus.setTextColor(0xFFF59E0B.toInt())
                SyncStatus.FAILED -> binding.tvSyncStatus.setTextColor(0xFFEF4444.toInt())
            }
        }
    }
}

