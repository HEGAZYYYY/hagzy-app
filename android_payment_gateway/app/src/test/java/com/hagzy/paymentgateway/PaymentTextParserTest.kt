package com.hagzy.paymentgateway

import com.hagzy.paymentgateway.util.PaymentTextParser
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentTextParserTest {

    @Test
    fun parsesEnglishInstaPayWithRecievedTypo() {
        val raw = "You have recieved 150.00 EGP from mohamedra4adhegazy@instapay"
        val event = PaymentTextParser.parseInstaPayNotification(raw, 1700000000000L)

        assertNotNull(event)
        assertEquals("INSTAPAY", event!!.paymentMethod)
        assertEquals(150.0, event.amount, 0.001)
        assertEquals("mohamedra4adhegazy@instapay", event.senderIdentifier)

        val json = JSONObject(event.toJsonString())
        assertEquals(raw, json.getString("text"))
        assertEquals(raw, json.getString("rawText"))
        assertEquals("mohamedra4adhegazy@instapay", json.getString("senderIdentifier"))
    }

    @Test
    fun parsesArabicInstaPayWithEasternArabicDigits() {
        val raw = "تم استلام تحويل بمبلغ ٢٠٠٫٠٠ ج.م من karim_aly@instapay بنجاح"
        val event = PaymentTextParser.parseInstaPayNotification(raw, 1700000000000L)

        assertNotNull(event)
        assertEquals("INSTAPAY", event!!.paymentMethod)
        assertEquals(200.0, event.amount, 0.001)
        assertEquals("karim_aly@instapay", event.senderIdentifier)
    }

    @Test
    fun parsesCommaThousandsAndDualPhoneNumbersExcludingReceiver() {
        val commaRaw = "You have received 1,250.00 EGP from abdelhamed1978@instapay"
        val commaEvent = PaymentTextParser.parseInstaPayNotification(commaRaw, 1700000000000L)
        assertNotNull(commaEvent)
        assertEquals(1250.0, commaEvent!!.amount, 0.001)
        assertEquals("abdelhamed1978@instapay", commaEvent.senderIdentifier)

        val dualPhoneRaw = "تم استلام مبلغ 1,250.00 جم بنجاح من 01091122334 إلى حسابك المرتبط برقم 01015325250 مرجع IP9921"
        val dualEvent = PaymentTextParser.parseInstaPayNotification(
            rawText = dualPhoneRaw,
            timestamp = 1700000000000L,
            receiverWallets = setOf("01015325250")
        )
        assertNotNull(dualEvent)
        assertEquals("INSTAPAY", dualEvent!!.paymentMethod)
        assertEquals(1250.0, dualEvent.amount, 0.001)
        assertEquals("01091122334", dualEvent.senderIdentifier)
        assertEquals("IP9921", dualEvent.providerRef)
        assertEquals("ip_ref_ip9921", dualEvent.eventId)
    }

    @Test
    fun parsesRealMultilineVodafoneCashSms() {
        val sms = "تم استلام مبلغ 100.00 جنيه من 01063330948؛\n" +
            "المسجل بإسم OMAR ISMAEL ABDELHAF\n" +
            "على رقم محفظتك 01041570557 بتاريخ 20:16 26-11-13.\n" +
            "رصيدك الحالي: 7.10 جنيه\n" +
            "رقم العملية: 025754378007\n" +
            "تقدر تتابع كل مصروفاتك من تاريخ المعاملات على أبلكيشن أنا فودافون http://vf.eg/vfcash"

        val event = PaymentTextParser.parseWalletSms(sms, 1700000000000L)

        assertNotNull(event)
        assertEquals("MOBILE_WALLET", event!!.paymentMethod)
        assertEquals(100.0, event.amount, 0.001)
        assertEquals("01063330948", event.senderIdentifier)
        assertEquals("025754378007", event.providerRef)
        assertEquals("mw_ref_025754378007", event.eventId)
    }

    @Test
    fun burstOfSimultaneousNotificationsProducesDistinctEventIdsWhileDuplicatesDeduplicate() {
        val ts = 1700000000000L
        val ids = HashSet<String>()

        for (i in 0 until 10) {
            val sender = "player_$i@instapay"
            val amount = 100.0 + i * 25.0
            val raw = "You have recieved ${"%.2f".format(java.util.Locale.US, amount)} EGP from $sender"
            val event = PaymentTextParser.parseInstaPayNotification(raw, ts)
            assertNotNull(event)
            assertTrue("Duplicate eventId generated for burst item $i", ids.add(event!!.eventId))
        }
        assertEquals(10, ids.size)

        // Same SMS received twice within 5 seconds (without providerRef) deduplicates to identical eventId
        val smsNoRef = "تم استلام مبلغ 150.00 جنيه من رقم 01012345678. رصيدك الحالي هو 1000.00 جنيه."
        val first = PaymentTextParser.parseWalletSms(smsNoRef, ts)
        val second = PaymentTextParser.parseWalletSms(smsNoRef, ts + 4000L)

        assertNotNull(first)
        assertNotNull(second)
        assertEquals(first!!.eventId, second!!.eventId)
    }

    @Test
    fun officialInstaPayAppFallbackForwardsUnknownSenderWithoutDropping() {
        val weirdRaw = "تم استلام تحويل بمبلغ 350.00 ج.م بنجاح عبر تطبيق إنستاباي"
        val nonOfficial = PaymentTextParser.parseInstaPayNotification(weirdRaw, 1700000000000L, isOfficialInstaPayApp = false)
        assertNull(nonOfficial)

        val official = PaymentTextParser.parseInstaPayNotification(weirdRaw, 1700000000000L, isOfficialInstaPayApp = true)
        assertNotNull(official)
        assertEquals("UNKNOWN_SENDER", official!!.senderIdentifier)
        assertEquals(350.0, official.amount, 0.001)

        val json = JSONObject(official.toJsonString())
        assertTrue(json.isNull("senderIdentifier"))
        assertEquals(350.0, json.getDouble("amount"), 0.001)
        assertEquals(weirdRaw, json.getString("text"))
    }
}
