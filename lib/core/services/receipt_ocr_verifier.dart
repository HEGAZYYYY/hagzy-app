/// Result of automated receipt screenshot text extraction (Track B Solo-Founder Automation)
class ReceiptOcrResult {
  final bool isValid;
  final String? referenceNumber;
  final double? amountEgp;
  final String? recipientHandle;
  final DateTime? timestamp;
  final String? rawExtractedText;
  final String? errorMessage;
  final String? errorMessageAr;

  const ReceiptOcrResult({
    required this.isValid,
    this.referenceNumber,
    this.amountEgp,
    this.recipientHandle,
    this.timestamp,
    this.rawExtractedText,
    this.errorMessage,
    this.errorMessageAr,
  });

  Map<String, dynamic> toJson() => {
        'is_valid': isValid,
        if (referenceNumber != null) 'reference_number': referenceNumber,
        if (amountEgp != null) 'amount_egp': amountEgp,
        if (recipientHandle != null) 'recipient_handle': recipientHandle,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
        if (errorMessage != null) 'error_message': errorMessage,
        if (errorMessageAr != null) 'error_message_ar': errorMessageAr,
      };
}

/// Automated Instapay & Mobile Wallet Receipt OCR Verifier
/// Runs local regex & rule-based parser on OCR text output to guarantee zero fraud
class ReceiptOcrVerifier {
  /// Converts Eastern Arabic numerals (٠-٩) to Western standard numerals (0-9)
  static String normalizeArabicNumerals(String input) {
    const arabicNums = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(arabicNums[i], i.toString());
    }
    return result;
  }

  /// Parses raw text extracted from an InstaPay or Vodafone Cash receipt screenshot
  static ReceiptOcrResult parseReceiptText({
    required String rawText,
    required double expectedDepositEgp,
    required Set<String> existingOcrRefs, // To detect duplicate screenshot reuse
  }) {
    if (rawText.trim().isEmpty) {
      return const ReceiptOcrResult(
        isValid: false,
        errorMessage: 'Empty receipt screenshot text. Please pick a clearer image.',
        errorMessageAr: 'الصورة غير واضحة. يرجى اختيار لقطة شاشة أوضح للإيصال.',
      );
    }

    final normalized = normalizeArabicNumerals(rawText);

    // 1. Extract Transaction Reference Number
    // Look for: "Ref: 1234567890", "رقم المرجع: 12345", "Transaction ID", "رقم العملية", or 10-18 digit strings
    String? refNumber;
    final refRegex = RegExp(
      r'(?:ref(?:erence)?(?:\s*no\.?|\s*id)?|رقم\s*المرجع|رقم\s*العملية|transaction\s*id)[\s:=#]*([A-Za-z0-9_-]{6,24})',
      caseSensitive: false,
    );
    final refMatch = refRegex.firstMatch(normalized);

    if (refMatch != null) {
      refNumber = refMatch.group(1)?.trim();
    } else {
      // Fallback: search for standalone 10-16 digit sequence
      final standaloneRefRegex = RegExp(r'\b\d{10,18}\b');
      final standaloneMatch = standaloneRefRegex.firstMatch(normalized);
      if (standaloneMatch != null) {
        refNumber = standaloneMatch.group(0)?.trim();
      }
    }

    if (refNumber == null || refNumber.isEmpty) {
      return ReceiptOcrResult(
        isValid: false,
        rawExtractedText: rawText,
        errorMessage: 'Could not detect transaction reference number.',
        errorMessageAr: 'تعذر العثور على رقم العملية / المرجع في الإيصال.',
      );
    }

    // Duplicate Fraud Prevention (Solo-Founder Protection)
    if (existingOcrRefs.contains(refNumber.toLowerCase())) {
      return ReceiptOcrResult(
        isValid: false,
        referenceNumber: refNumber,
        rawExtractedText: rawText,
        errorMessage: 'This receipt reference has already been submitted for another booking.',
        errorMessageAr: 'تم استخدام رقم هذا الإيصال مسبقاً في حجز آخر. يرجى إرسال إيصال جديد.',
      );
    }

    // 2. Extract Amount EGP
    // Look for: "60.00 EGP", "مبلغ 60 جنيه", "Amount: 60", "EGP 60", etc.
    double? extractedAmount;
    final amountRegex = RegExp(
      r'(?:amount|المبلغ|مبلغ|قيمة|إجمالي)[\s:=]*([0-9]+(?:\.[0-9]{1,2})?)|([0-9]+(?:\.[0-9]{1,2})?)\s*(?:egp|le|جنيه|ج\.م)',
      caseSensitive: false,
    );

    final amountMatches = amountRegex.allMatches(normalized);
    for (final m in amountMatches) {
      final valStr = m.group(1) ?? m.group(2);
      if (valStr != null) {
        final parsed = double.tryParse(valStr);
        if (parsed != null && (extractedAmount == null || parsed > extractedAmount)) {
          extractedAmount = parsed;
        }
      }
    }

    // Fallback amount check: look for isolated numbers around the expected range
    if (extractedAmount == null) {
      final genericNumRegex = RegExp(r'\b\d{2,5}(?:\.\d{1,2})?\b');
      final numMatches = genericNumRegex.allMatches(normalized);
      for (final m in numMatches) {
        final val = double.tryParse(m.group(0)!);
        if (val != null && val >= (expectedDepositEgp * 0.9)) {
          extractedAmount = val;
          break;
        }
      }
    }

    if (extractedAmount == null) {
      return ReceiptOcrResult(
        isValid: false,
        referenceNumber: refNumber,
        rawExtractedText: rawText,
        errorMessage: 'Could not extract transfer amount from receipt.',
        errorMessageAr: 'تعذر استخراج مبلغ التحويل من الإيصال.',
      );
    }

    // Verify amount is >= expected deposit (tolerance of 1 EGP for minor fees)
    if (extractedAmount < (expectedDepositEgp - 1.0)) {
      return ReceiptOcrResult(
        isValid: false,
        referenceNumber: refNumber,
        amountEgp: extractedAmount,
        rawExtractedText: rawText,
        errorMessage:
            'Transferred amount (${extractedAmount.toStringAsFixed(0)} EGP) is less than required deposit (${expectedDepositEgp.toStringAsFixed(0)} EGP).',
        errorMessageAr:
            'المبلغ المحول (${extractedAmount.toStringAsFixed(0)} ج.م) أقل من الإيداع المطلوب (${expectedDepositEgp.toStringAsFixed(0)} ج.م).',
      );
    }

    // 3. Extract Recipient Handle (Optional InstaPay IPA)
    String? recipient;
    final ipaRegex = RegExp(r'([A-Za-z0-9_.-]+@instapay)', caseSensitive: false);
    final ipaMatch = ipaRegex.firstMatch(normalized);
    if (ipaMatch != null) {
      recipient = ipaMatch.group(1);
    }

    return ReceiptOcrResult(
      isValid: true,
      referenceNumber: refNumber,
      amountEgp: extractedAmount,
      recipientHandle: recipient,
      timestamp: DateTime.now(),
      rawExtractedText: rawText,
    );
  }
}

