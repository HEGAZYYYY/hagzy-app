import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';
import '../../core/services/receipt_ocr_verifier.dart';

/// Automated InstaPay & Mobile Wallet Receipt OCR Upload Sheet (Track B Solo-Founder Automation)
class AutomatedReceiptUploadSheet extends StatefulWidget {
  final HagzyBooking booking;
  final String instapayAddress;
  final String walletNumber;
  final Set<String> existingOcrRefs;
  final ValueChanged<ReceiptOcrResult> onVerified;
  final bool isArabic;

  const AutomatedReceiptUploadSheet({
    super.key,
    required this.booking,
    this.instapayAddress = 'mohamedra4adhegazy@instapay',
    this.walletNumber = '01012345678',
    this.existingOcrRefs = const {},
    required this.onVerified,
    this.isArabic = false,
  });

  @override
  State<AutomatedReceiptUploadSheet> createState() =>
      _AutomatedReceiptUploadSheetState();
}

class _AutomatedReceiptUploadSheetState
    extends State<AutomatedReceiptUploadSheet> {
  final _receiptTextController = TextEditingController();
  bool _isProcessing = false;
  ReceiptOcrResult? _ocrResult;

  @override
  void dispose() {
    _receiptTextController.dispose();
    super.dispose();
  }

  void _runVerification(String rawText) {
    setState(() => _isProcessing = true);

    final result = ReceiptOcrVerifier.parseReceiptText(
      rawText: rawText,
      expectedDepositEgp: widget.booking.depositRequiredEgp,
      existingOcrRefs: widget.existingOcrRefs,
    );

    setState(() {
      _isProcessing = false;
      _ocrResult = result;
    });

    if (result.isValid) {
      widget.onVerified(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAr = widget.isArabic;
    final deposit = widget.booking.depositRequiredEgp.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAr ? 'تأكيد الإيداع بالذكاء الاصطناعي (OCR)' : 'Automated Deposit OCR Verification',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Payout Target Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAr ? 'العربون المطلوب تحويله:' : 'Required Deposit:',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                    Text(
                      '$deposit ${isAr ? "ج.م" : "EGP"}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'InstaPay: ${widget.instapayAddress}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Vodafone Cash: ${widget.walletNumber}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // OCR input / Paste area
          TextField(
            controller: _receiptTextController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: isAr
                  ? 'الصق نص الإيصال من تطبيق إنستاباي أو فودافون كاش هنا للتحقق الفوري...'
                  : 'Paste receipt text from InstaPay or Mobile Wallet for instant verification...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),

          // OCR Result feedback banner
          if (_ocrResult != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _ocrResult!.isValid
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _ocrResult!.isValid ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _ocrResult!.isValid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    color: _ocrResult!.isValid ? Colors.greenAccent : Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _ocrResult!.isValid
                          ? (isAr
                              ? 'تم التحقق بنجاح! رقم المرجع: ${_ocrResult!.referenceNumber} • تم دفع ${_ocrResult!.amountEgp?.toStringAsFixed(0)} ج.م'
                              : 'Verified! Ref: ${_ocrResult!.referenceNumber} • Amount: ${_ocrResult!.amountEgp?.toStringAsFixed(0)} EGP')
                          : (isAr ? _ocrResult!.errorMessageAr ?? 'بيانات الإيصال غير صحيحة' : _ocrResult!.errorMessage ?? 'Invalid receipt'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ocrResult!.isValid ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _runVerification(_receiptTextController.text),
              icon: _isProcessing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                isAr ? 'التحقق الآلي من الإيصال وتأكيد الحجز' : 'Verify Receipt & Confirm Booking',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

