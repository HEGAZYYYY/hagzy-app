import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/hagzy_theme.dart';

/// Modal bottom sheet allowing the customer to enter any custom top-up amount
/// or pick from fast preset chips, then immediately proceed to the payments section.
class TopUpWalletSheet extends StatefulWidget {
  const TopUpWalletSheet({
    super.key,
    required this.currentBalance,
    this.isArabic = false,
    required this.onProceedToPayment,
  });

  final double currentBalance;
  final bool isArabic;
  final ValueChanged<double> onProceedToPayment;

  static Future<void> show({
    required BuildContext context,
    required double currentBalance,
    bool isArabic = false,
    required ValueChanged<double> onProceedToPayment,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TopUpWalletSheet(
        currentBalance: currentBalance,
        isArabic: isArabic,
        onProceedToPayment: onProceedToPayment,
      ),
    );
  }

  @override
  State<TopUpWalletSheet> createState() => _TopUpWalletSheetState();
}

class _TopUpWalletSheetState extends State<TopUpWalletSheet> {
  late final TextEditingController _amountController;
  final _formKey = GlobalKey<FormState>();
  double _selectedAmount = 100.0;
  static const List<double> _presets = [50.0, 100.0, 200.0, 500.0, 1000.0];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: '100');
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onPresetTapped(double preset) {
    setState(() {
      _selectedAmount = preset;
      _amountController.text = preset.toInt().toString();
    });
  }

  void _submit() {
    final raw = _amountController.text.trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 5.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
          content: Text(
            widget.isArabic
                ? 'الحد الأدنى للشحن عبر انستاباي وفودافون كاش هو ٥ جنيه'
                : 'Minimum top-up amount on InstaPay & Vodafone Cash is 5 EGP',
          ),
        ),
      );
      return;
    }

    Navigator.pop(context);
    widget.onProceedToPayment(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark || kDarkMode.value;
    final arabic = widget.isArabic;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131C31) : kPanel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: kGreen.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            ...HagzyTheme.softShadow,
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: HagzyTheme.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: HagzyTheme.brandGlowShadow,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          arabic ? 'شحن محفظة حجزي' : 'Top Up Hagzy Wallet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: kInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          arabic
                              ? 'رصيدك الحالي: ${widget.currentBalance.toStringAsFixed(0)} ج.م'
                              : 'Current Balance: ${widget.currentBalance.toStringAsFixed(0)} EGP',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: kMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: arabic ? 'إغلاق' : 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Custom Amount Input
              Text(
                arabic ? 'أدخل مبلغ الشحن المطلوب:' : 'Enter Top-Up Amount:',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: kGreen,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.payments_outlined, color: kGreen),
                  suffixText: arabic ? 'ج.م' : 'EGP',
                  suffixStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: kGreen,
                  ),
                  hintText: '100',
                  helperText: arabic
                      ? 'الحد الأدنى ٥ جنيه (شرط شبكة انستاباي وفودافون كاش)'
                      : 'Minimum 5 EGP (InstaPay & Vodafone Cash limit)',
                  helperStyle: TextStyle(
                    color: kMuted,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0F172A)
                      : kSurfaceTint.withValues(alpha: 0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kGreen, width: 2),
                  ),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null) {
                    setState(() => _selectedAmount = parsed);
                  }
                },
              ),
              const SizedBox(height: 14),

              // Quick Amount Preset Chips
              Text(
                arabic ? 'أو اختر مبلغاً سريعاً:' : 'Or Select Quick Amount:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _presets.map((preset) {
                  final isSelected = (_selectedAmount == preset) &&
                      (_amountController.text == preset.toInt().toString());
                  return ChoiceChip(
                    label: Text('+${preset.toInt()} ${arabic ? "ج.م" : "EGP"}'),
                    selected: isSelected,
                    selectedColor: kGreen.withValues(alpha: 0.25),
                    backgroundColor: isDark
                        ? const Color(0xFF0F172A)
                        : kSurfaceTint.withValues(alpha: 0.5),
                    labelStyle: TextStyle(
                      color: isSelected ? kGreen : kInk,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected ? kGreen : kBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                    onSelected: (_) => _onPresetTapped(preset),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Continue to Payment CTA
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                onPressed: _submit,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: Text(
                  arabic
                      ? 'متابعة إلى الدفع (${_selectedAmount.toStringAsFixed(0)} ج.م) ←'
                      : 'Continue to Payment (${_selectedAmount.toStringAsFixed(0)} EGP) →',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

