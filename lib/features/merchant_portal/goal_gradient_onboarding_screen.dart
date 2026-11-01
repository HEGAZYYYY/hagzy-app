import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';
import 'category_templates.dart';

/// Merchant Onboarding Flow
/// Clean, validated 2-step setup for venue merchants
class GoalGradientOnboardingScreen extends StatefulWidget {
  final String ownerId;
  final ValueChanged<HagzyVenue> onVenueCreated;
  final bool isArabic;

  const GoalGradientOnboardingScreen({
    super.key,
    required this.ownerId,
    required this.onVenueCreated,
    this.isArabic = false,
  });

  @override
  State<GoalGradientOnboardingScreen> createState() =>
      _GoalGradientOnboardingScreenState();
}

class _GoalGradientOnboardingScreenState
    extends State<GoalGradientOnboardingScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _instapayController = TextEditingController();
  final _walletController = TextEditingController();

  String _selectedCity = 'Kafr El Sheikh';
  final Set<String> _selectedCategories = {'playstation'};
  final double _lat = 31.1107;
  final double _lng = 30.9388;

  int _currentStepIndex = 1; // Honest 2-step onboarding (Step 1: Info, Step 2: Payouts)

  final List<String> _availableCities = [
    'Kafr El Sheikh',
    'Tanta',
    'New Cairo',
    'Alexandria',
    'Mansoura',
    'Giza',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _instapayController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  void _finishOnboarding() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isArabic ? 'يرجى إدخال اسم المكان' : 'Please enter venue name')),
      );
      return;
    }

    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isArabic ? 'يرجى إدخال العنوان بالتفصيل' : 'Please enter detailed address')),
      );
      return;
    }

    final instapay = _instapayController.text.trim();
    final wallet = _walletController.text.trim();
    if (instapay.isEmpty && wallet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isArabic
              ? 'يرجى إدخال عنوان إنستاباي أو رقم محفظة إلكترونية لاستلام العربون'
              : 'Please enter an InstaPay address or mobile wallet number to receive deposits'),
        ),
      );
      return;
    }

    if (wallet.isNotEmpty && !RegExp(r'^01[0125]\d{8}$').hasMatch(wallet)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isArabic
              ? 'رقم المحفظة غير صالح (يجب أن يتكون من 11 رقماً ويبدأ بـ 010 أو 011 أو 012 أو 015)'
              : 'Invalid mobile wallet number (must be 11 Egyptian digits)'),
        ),
      );
      return;
    }

    final venueId = 'ven_${DateTime.now().millisecondsSinceEpoch}';

    // Collect pre-loaded units from selected category templates
    final allUnits = <BookableUnit>[];
    for (final cat in _selectedCategories) {
      allUnits.addAll(
        CategoryTemplates.getTemplateUnitsForCategory(
          category: cat,
          venueId: venueId,
        ),
      );
    }

    final venue = HagzyVenue(
      id: venueId,
      ownerId: widget.ownerId,
      name: name,
      city: _selectedCity,
      address: address,
      lat: _lat,
      lng: _lng,
      categories: _selectedCategories.toList(),
      instapayAddress: instapay.isNotEmpty ? instapay : null,
      walletNumber: wallet.isNotEmpty ? wallet : null,
      units: allUnits,
      createdAt: DateTime.now(),
    );

    widget.onVenueCreated(venue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAr = widget.isArabic;

    // Honest 2-step progress: Step 1 = 50%, Step 2 = 100%
    final progress = _currentStepIndex == 1 ? 0.50 : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAr ? 'تسجيل مكان جديد' : 'List Your Venue',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Step Progress Card
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAr ? 'نسبة اكتمال إعداد حسابك' : 'Setup Progress',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${(progress * 100).toInt()}% ${isAr ? "مكتمل" : "Complete"}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                // Checklist Items
                _buildChecklistRow(
                  isDone: _currentStepIndex > 1,
                  isCurrent: _currentStepIndex == 1,
                  text: isAr
                      ? 'الخطوة ١: بيانات المكان والموقع 📍'
                      : 'Step 1: Venue Info & Location 📍',
                ),
                _buildChecklistRow(
                  isDone: false,
                  isCurrent: _currentStepIndex == 2,
                  text: isAr
                      ? 'الخطوة ٢: بيانات استلام العربون والأرباح 💳'
                      : 'Step 2: Payout & Deposit Details 💳',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_currentStepIndex == 1) ...[
                  // Step 1 Content: Name, Categories & Location
                  Text(
                    isAr ? 'الخطوة ١: بيانات المكان والموقع' : 'Step 1: Venue Info & Location',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: isAr ? 'اسم المكان / الصالة' : 'Venue Name',
                      hintText: isAr ? 'مثال: ستارز لاونج (Stars Lounge)' : 'e.g. Stars Lounge',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Category Multiselect
                  Text(
                    isAr ? 'الأنشطة المتاحة في المكان' : 'Available Activities in Venue',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      'playstation',
                      'billiards',
                      'ping_pong',
                      'workspace',
                      'escape_room',
                      'barber',
                      'court',
                    ].map((cat) {
                      final isSelected = _selectedCategories.contains(cat);
                      return FilterChip(
                        label: Text(cat.toUpperCase()),
                        selected: isSelected,
                        selectedColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedCategories.add(cat);
                            } else {
                              if (_selectedCategories.length > 1) {
                                _selectedCategories.remove(cat);
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // City Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCity,
                    decoration: InputDecoration(
                      labelText: isAr ? 'المدينة / المحافظة' : 'City / Governorate',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: _availableCities
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCity = v ?? _selectedCity),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: isAr ? 'العنوان بالتفصيل' : 'Detailed Address',
                      hintText: isAr ? 'الشارع، بجوار معلم معروف' : 'Street name, nearby landmark',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ] else ...[
                  // Step 2 Content: Payouts & Payout details
                  Text(
                    isAr ? 'الخطوة ٢: بيانات استلام العربون والأرباح' : 'Step 2: Payout & Deposit Details',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAr
                        ? 'العربون بيتحول لك مباشرة وفورياً بدون أي وسيط مالي.'
                        : 'Customer deposits transfer directly & instantly to you with zero delay.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _instapayController,
                    decoration: InputDecoration(
                      labelText: isAr ? 'معرّف إنستاباي (InstaPay Handle)' : 'InstaPay Handle',
                      hintText: 'username@instapay',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _walletController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: isAr ? 'رقم محفظة فودافون كاش / أورنج' : 'Mobile Wallet Number',
                      hintText: '010xxxxxxxx',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Bottom Action Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () {
                  if (_currentStepIndex == 1) {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isAr ? 'يرجى إدخال اسم المكان' : 'Please enter venue name')),
                      );
                      return;
                    }
                    final address = _addressController.text.trim();
                    if (address.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isAr ? 'يرجى إدخال العنوان بالتفصيل' : 'Please enter detailed address')),
                      );
                      return;
                    }
                    setState(() => _currentStepIndex = 2);
                  } else {
                    _finishOnboarding();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  _currentStepIndex == 1
                      ? (isAr ? 'متابعة للخطوة الأخيرة ←' : 'Continue to Final Step →')
                      : (isAr ? 'نشر المكان وبدء استقبال الحجوزات 🚀' : 'Publish Venue & Launch 🚀'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistRow({
    required bool isDone,
    bool isCurrent = false,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.0,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isDone
              ? Colors.greenAccent
              : (isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

