package com.hagzy.paymentgateway.util

import com.hagzy.paymentgateway.data.model.PaymentEvent
import com.hagzy.paymentgateway.data.model.SyncStatus
import java.security.MessageDigest
import java.util.Locale
import java.util.regex.Pattern

object PaymentTextParser {

    val DEFAULT_RECEIVER_WALLETS = setOf(
        "01015325250",
        "01041570557"
    )

    private val DIRECTIONAL_MARKS_REGEX = Regex("[\u200E\u200F\u202A-\u202E\u061C]")
    private val THOUSAND_SEPARATOR_REGEX = Regex("(?<=\\d)[,٬](?=\\d{3}(?:\\D|$))")
    private val INSTAPAY_HANDLE_PATTERN = Pattern.compile(
        """([a-zA-Z0-9._-]+@instapay)""",
        Pattern.CASE_INSENSITIVE
    )
    private val EXPLICIT_INSTAPAY_HANDLE_PATTERN = Pattern.compile(
        """(?:من|from)\s+([a-zA-Z0-9._-]+@instapay)""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )
    private val EXPLICIT_PHONE_PATTERN = Pattern.compile(
        """(?:من\s+رقم|من|from\s+number|from)\s*(?:\+?2)?(01[0125][0-9]{8})""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )
    private val GENERIC_FROM_HANDLE_PATTERN = Pattern.compile(
        """(?:من|from)\s+([a-zA-Z0-9._-]{3,})""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )
    private val ANY_EGYPT_PHONE_PATTERN = Pattern.compile(
        """(?:\+?2)?(01[0125][0-9]{8})"""
    )
    private val RECEIVER_PRECEDING_PHONE_PATTERN = Pattern.compile(
        """(?:على\s+رقم\s+محفظتك|رقم\s+محفظتك|المرتبط\s+برقم|إلى\s+حسابك|إلى\s+رقم|إلى|الى|to\s+wallet|to)\s*(?:رقم\s*)?(?:\+?2)?(01[0125][0-9]{8})""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )
    private val PROVIDER_REF_PATTERN = Pattern.compile(
        """(?:\b(?:Transaction\s*ID|Ref(?:\s*ID|erence)?)|رقم\s*العملية|المرجع|مرجع)[:#\-\s]+([A-Za-z0-9]{4,})""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )

    private val AMOUNT_PATTERNS = listOf(
        Pattern.compile(
            """(?:تم\s+استلام\s+تحويل\s+بمبلغ|تم\s+استلام\s+مبلغ|تم\s+إيداع\s+مبلغ|تم\s+إيداع|تم\s+تحويل\s+مبلغ|تم\s+استلام|استلمت\s+مبلغ|استلمت|مبلغ|بمبلغ|بقيمة|قيمة)\s*([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|ج\s*م|egp|le)?""",
            Pattern.CASE_INSENSITIVE or Pattern.DOTALL
        ),
        Pattern.compile(
            """(?:you\s+have\s+received|you\s+have\s+recieved|received|recieved|transfer\s+of|deposited)\s*(?:egp|le|ج\.م|جنيه)?\s*([0-9]+(?:\.[0-9]+)?)""",
            Pattern.CASE_INSENSITIVE or Pattern.DOTALL
        ),
        Pattern.compile(
            """([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le|جنيه|جنيها|ج\.م|جم|ج\s*م)\s*(?:received|recieved|from|من)""",
            Pattern.CASE_INSENSITIVE or Pattern.DOTALL
        )
    )

    private val GENERIC_AMOUNT_PATTERN = Pattern.compile(
        """([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le|جنيه|جنيها|ج\.م|جم|ج\s*م)""",
        Pattern.CASE_INSENSITIVE or Pattern.DOTALL
    )

    private val TRANSFER_KEYWORDS_REGEX = Regex(
        """(egp|ج\.م|جم|جنيه|استلام|استلمت|تحويل|إيداع|ايداع|received|recieved|transfer|deposited)""",
        RegexOption.IGNORE_CASE
    )
    private val INCOMING_WALLET_KEYWORDS_REGEX = Regex(
        """(استلام|استلمت|إيداع|ايداع|received|recieved|deposited|تم\s+تحويل.*?\sمن\s)""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )
    private val OUTGOING_ONLY_REGEX = Regex(
        """(?:تم\s+تحويل|تم\s+إرسال|sent|transferred)\s+.*?(?:إلى|الى|to)\s*(?:\+?2)?01""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )
    private val NON_SENDER_WORDS = setOf(
        "رقم", "حساب", "محفظة", "بنك", "bank", "account", "number", "instapay", "egp", "le"
    )
    private val BALANCE_OR_FEE_PREFIX_REGEX = Regex(
        """(?:رصيدك|رصيد|balance|مصاريف|fee|fees)[^0-9]{0,20}$""",
        RegexOption.IGNORE_CASE
    )

    fun normalizeDigitsAndCommas(input: String): String {
        if (input.isEmpty()) return ""
        val sb = StringBuilder(input.length)
        for (ch in input) {
            when (ch) {
                '٠' -> sb.append('0')
                '١' -> sb.append('1')
                '٢' -> sb.append('2')
                '٣' -> sb.append('3')
                '٤' -> sb.append('4')
                '٥' -> sb.append('5')
                '٦' -> sb.append('6')
                '٧' -> sb.append('7')
                '٨' -> sb.append('8')
                '٩' -> sb.append('9')
                '٫' -> sb.append('.')
                else -> sb.append(ch)
            }
        }
        val strippedMarkers = sb.toString().replace(DIRECTIONAL_MARKS_REGEX, "")
        return strippedMarkers.replace(THOUSAND_SEPARATOR_REGEX, "")
    }

    fun normalizeEgyptianPhone(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val digits = normalizeDigitsAndCommas(raw).filter { it.isDigit() }
        if (digits.isEmpty()) return null
        val local = when {
            digits.startsWith("0020") && digits.length >= 14 -> digits.substring(4)
            digits.startsWith("20") && digits.length >= 12 -> digits.substring(2)
            else -> digits
        }
        val normalized = if (local.length == 10 && Regex("^(10|11|12|15)\\d{8}$").matches(local)) {
            "0$local"
        } else {
            local
        }
        return if (Regex("^01[0125][0-9]{8}$").matches(normalized)) normalized else null
    }

    fun parseInstaPayNotification(
        rawText: String,
        timestamp: Long,
        receiverWallets: Set<String> = emptySet(),
        isOfficialInstaPayApp: Boolean = false
    ): PaymentEvent? {
        if (rawText.isBlank()) return null
        val normalized = normalizeDigitsAndCommas(rawText)
        val excluded = buildExcludedReceiverSet(receiverWallets)

        val amount = extractAmount(normalized)
        val senderIdentifier = extractInstaPaySender(normalized, excluded)
        val providerRef = extractProviderRef(normalized)

        if (amount != null && senderIdentifier != null) {
            val eventId = computeEventId(
                paymentMethod = "INSTAPAY",
                senderIdentifier = senderIdentifier,
                amount = amount,
                providerRef = providerRef,
                rawText = rawText,
                timestamp = timestamp
            )
            return PaymentEvent(
                eventId = eventId,
                paymentMethod = "INSTAPAY",
                senderIdentifier = senderIdentifier,
                amount = amount,
                providerRef = providerRef,
                rawText = rawText,
                timestamp = timestamp,
                syncStatus = SyncStatus.PENDING
            )
        }

        if (isOfficialInstaPayApp && TRANSFER_KEYWORDS_REGEX.containsMatchIn(normalized)) {
            val fallbackSender = senderIdentifier ?: "UNKNOWN_SENDER"
            val fallbackAmount = amount ?: 0.0
            val eventId = computeEventId(
                paymentMethod = "INSTAPAY",
                senderIdentifier = fallbackSender,
                amount = fallbackAmount,
                providerRef = providerRef,
                rawText = rawText,
                timestamp = timestamp
            )
            return PaymentEvent(
                eventId = eventId,
                paymentMethod = "INSTAPAY",
                senderIdentifier = fallbackSender,
                amount = fallbackAmount,
                providerRef = providerRef,
                rawText = rawText,
                timestamp = timestamp,
                syncStatus = SyncStatus.PENDING
            )
        }

        return null
    }

    fun parseWalletSms(
        rawText: String,
        timestamp: Long,
        receiverWallets: Set<String> = emptySet()
    ): PaymentEvent? {
        if (rawText.isBlank()) return null
        val normalized = normalizeDigitsAndCommas(rawText)

        // Avoid treating outgoing transfers as incoming deposits
        if (OUTGOING_ONLY_REGEX.containsMatchIn(normalized) &&
            !INCOMING_WALLET_KEYWORDS_REGEX.containsMatchIn(normalized)
        ) {
            return null
        }

        val excluded = buildExcludedReceiverSet(receiverWallets)
        val amount = extractAmount(normalized) ?: return null
        val senderPhone = extractWalletSenderPhone(normalized, excluded) ?: return null
        val providerRef = extractProviderRef(normalized)

        val eventId = computeEventId(
            paymentMethod = "MOBILE_WALLET",
            senderIdentifier = senderPhone,
            amount = amount,
            providerRef = providerRef,
            rawText = rawText,
            timestamp = timestamp
        )

        return PaymentEvent(
            eventId = eventId,
            paymentMethod = "MOBILE_WALLET",
            senderIdentifier = senderPhone,
            amount = amount,
            providerRef = providerRef,
            rawText = rawText,
            timestamp = timestamp,
            syncStatus = SyncStatus.PENDING
        )
    }

    fun computeEventId(
        paymentMethod: String,
        senderIdentifier: String,
        amount: Double,
        providerRef: String?,
        rawText: String,
        timestamp: Long
    ): String {
        val prefix = if (paymentMethod == "INSTAPAY") "ip" else "mw"
        val cleanRef = providerRef?.trim()
        if (!cleanRef.isNullOrEmpty()) {
            return "${prefix}_ref_${cleanRef.lowercase(Locale.US)}"
        }
        val timeBucket = timestamp / 10_000L
        val amountFormatted = "%.2f".format(Locale.US, amount)
        val hashInput = "$paymentMethod:${senderIdentifier.trim().lowercase(Locale.US)}:$amountFormatted:$timeBucket:${rawText.trim().hashCode()}"
        return "${prefix}_${sha256(hashInput).take(24)}"
    }

    private fun buildExcludedReceiverSet(receiverWallets: Set<String>): Set<String> {
        val out = HashSet<String>()
        for (raw in DEFAULT_RECEIVER_WALLETS + receiverWallets) {
            val trimmed = raw.trim().lowercase(Locale.US)
            if (trimmed.isNotEmpty()) out.add(trimmed)
            normalizeEgyptianPhone(raw)?.let { out.add(it) }
        }
        return out
    }

    private fun extractAmount(normalized: String): Double? {
        for (pattern in AMOUNT_PATTERNS) {
            val matcher = pattern.matcher(normalized)
            while (matcher.find()) {
                val startIdx = matcher.start()
                val prefixWindow = normalized.substring(maxOf(0, startIdx - 32), startIdx)
                if (BALANCE_OR_FEE_PREFIX_REGEX.containsMatchIn(prefixWindow)) continue
                val value = matcher.group(1)?.toDoubleOrNull()
                if (value != null && value > 0.0) return value
            }
        }
        if (TRANSFER_KEYWORDS_REGEX.containsMatchIn(normalized)) {
            val matcher = GENERIC_AMOUNT_PATTERN.matcher(normalized)
            while (matcher.find()) {
                val startIdx = matcher.start()
                val prefixWindow = normalized.substring(maxOf(0, startIdx - 32), startIdx)
                if (BALANCE_OR_FEE_PREFIX_REGEX.containsMatchIn(prefixWindow)) continue
                val value = matcher.group(1)?.toDoubleOrNull()
                if (value != null && value > 0.0) return value
            }
        }
        return null
    }

    private fun extractProviderRef(normalized: String): String? {
        val matcher = PROVIDER_REF_PATTERN.matcher(normalized)
        return if (matcher.find()) matcher.group(1)?.trim() else null
    }

    private fun extractInstaPaySender(normalized: String, excluded: Set<String>): String? {
        val explicitIpaMatcher = EXPLICIT_INSTAPAY_HANDLE_PATTERN.matcher(normalized)
        while (explicitIpaMatcher.find()) {
            val handle = explicitIpaMatcher.group(1)?.trim()?.lowercase(Locale.US) ?: continue
            val localPhone = normalizeEgyptianPhone(handle.substringBefore("@"))
            if (localPhone == null || !excluded.contains(localPhone)) {
                return handle
            }
        }

        val ipaMatcher = INSTAPAY_HANDLE_PATTERN.matcher(normalized)
        while (ipaMatcher.find()) {
            val handle = ipaMatcher.group(1)?.trim()?.lowercase(Locale.US) ?: continue
            val localPhone = normalizeEgyptianPhone(handle.substringBefore("@"))
            if (localPhone == null || !excluded.contains(localPhone)) {
                return handle
            }
        }

        val explicitPhoneMatcher = EXPLICIT_PHONE_PATTERN.matcher(normalized)
        while (explicitPhoneMatcher.find()) {
            val phone = explicitPhoneMatcher.group(1)?.trim() ?: continue
            if (!excluded.contains(phone)) return phone
        }

        val genericFromMatcher = GENERIC_FROM_HANDLE_PATTERN.matcher(normalized)
        while (genericFromMatcher.find()) {
            val candidate = genericFromMatcher.group(1)?.trim() ?: continue
            val lower = candidate.lowercase(Locale.US)
            if (NON_SENDER_WORDS.contains(lower)) continue
            val asPhone = normalizeEgyptianPhone(candidate)
            if (asPhone != null) {
                if (!excluded.contains(asPhone)) return asPhone
            } else if (candidate.any { it.isLetter() }) {
                val handle = if (lower.endsWith("@instapay")) lower else "$lower@instapay"
                if (!excluded.contains(handle)) return handle
            }
        }

        val receiverPhones = collectReceiverTaggedPhones(normalized)
        val anyPhoneMatcher = ANY_EGYPT_PHONE_PATTERN.matcher(normalized)
        while (anyPhoneMatcher.find()) {
            val phone = anyPhoneMatcher.group(1)?.trim() ?: continue
            if (!excluded.contains(phone) && !receiverPhones.contains(phone)) {
                return phone
            }
        }

        return null
    }

    private fun extractWalletSenderPhone(normalized: String, excluded: Set<String>): String? {
        val explicitPhoneMatcher = EXPLICIT_PHONE_PATTERN.matcher(normalized)
        while (explicitPhoneMatcher.find()) {
            val phone = explicitPhoneMatcher.group(1)?.trim() ?: continue
            if (!excluded.contains(phone)) return phone
        }

        val receiverPhones = collectReceiverTaggedPhones(normalized)
        val anyPhoneMatcher = ANY_EGYPT_PHONE_PATTERN.matcher(normalized)
        while (anyPhoneMatcher.find()) {
            val phone = anyPhoneMatcher.group(1)?.trim() ?: continue
            if (!excluded.contains(phone) && !receiverPhones.contains(phone)) {
                return phone
            }
        }

        return null
    }

    private fun collectReceiverTaggedPhones(normalized: String): Set<String> {
        val tagged = HashSet<String>()
        val matcher = RECEIVER_PRECEDING_PHONE_PATTERN.matcher(normalized)
        while (matcher.find()) {
            matcher.group(1)?.trim()?.let { tagged.add(it) }
        }
        return tagged
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
