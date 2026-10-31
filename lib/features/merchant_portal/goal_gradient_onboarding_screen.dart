import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';
import 'category_templates.dart';

/// Merchant Onboarding Flow Enforcing Principle 3 (The Goal Gradient Effect)
/// Progress starts at 40% Complete (steps 1 & 2 pre-completed) to maximize completion rates
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
  double? _lat = 31.1107;
  double? _lng = 30.9388;

  int _currentStepIndex = 2; // Step 0 and 1 are 100% complete (40% initial head-start!)

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
    final venueId = 'ven_${DateTime.now().millisecondsSinceEpoch}';
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'My Lounge / Venue';

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
      address: _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : 'Central Street, $_selectedCity',
      lat: _lat,
      lng: _lng,
      categories: _selectedCategories.toList(),
      instapayAddress: _instapayController.text.trim().isNotEmpty
          ? _instapayController.text.trim()
          : null,
      walletNumber: _walletController.text.trim().isNotEmpty
          ? _walletController.text.trim()
          : null,
      units: allUnits,
      createdAt: DateTime.now(),
    );

    widget.onVenueCreated(venue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAr = widget.isArabic;

    // Progress: Step 3 = 70%, Step 4 = 100%
    final progress = _currentStepIndex == 2 ? 0.40 : 0.85;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAr ? 'تسجيل مكان جديد (خطوات سريعة)' : 'List Your Venue (Fast-Track)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Goal Gradient Progress Card (Principle 3)
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
                    backgroundColor: theme.colorScheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                // Checklist Items
                _buildChecklistRow(
                  isDone: true,
                  text: isAr ? 'تم تفعيل حساب الشريك ✅' : 'Partner Account Initialized ✅',
                ),
                _buildChecklistRow(
                  isDone: true,
                  text: isAr
                      ? 'تم تحميل قوالب الأسعار والغرف تلقائياً ✅'
                      : 'Default Category Templates Loaded ✅',
                ),
                _buildChecklistRow(
                  isDone: _currentStepIndex > 2,
                  isCurrent: _currentStepIndex == 2,
                  text: isAr
                      ? 'اسم المكان وموقع الـ GPS 🔄'
                      : 'Venue Name & 1-Tap GPS Pin 🔄',
                ),
                _buildChecklistRow(
                  isDone: false,
                  isCurrent: _currentStepIndex == 3,
                  text: isAr
                      ? 'حساب إنستاباي / المحفظة لاستلام الأرباح ⏳'
                      : 'Instapay / Wallet Number for Payouts ⏳',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_currentStepIndex == 2) ...[
                  // Step 3 Content: Name, Categories & Location
                  Text(
                    isAr ? 'الخطوة ٣: بيانات المكان والموقع' : 'Step 3: Venue Info & Location',
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
                    value: _selectedCity,
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
                  // Step 4 Content: Payouts & Payout details
                  Text(
                    isAr ? 'الخطوة ٤: بيانات استلام العربون والأرباح' : 'Step 4: Payout Details',
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
                  if (_currentStepIndex == 2) {
                    setState(() => _currentStepIndex = 3);
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
                  _currentStepIndex == 2
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
          fontSize: 11.5,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isDone
              ? Colors.greenAccent
              : (isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

