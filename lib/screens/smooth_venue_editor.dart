import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/image_upload_service.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/smart_image.dart';

/// Clean, smooth, non-AI venue editor & creator for Hagzy owners.
/// Allows direct configuration of:
/// 1. Venue Details & Category
/// 2. Rooms, Courts, and Salon Chairs with time-based pricing
/// 3. Salon Services & Add-ons
/// 4. Photos (with instant live preview & quick presets)
/// 5. Payment Accounts (Vodafone Cash, InstaPay, Deposit %)
/// 6. Owner Accounts (Name, Phone, Email)
/// 7. Amenities & Operating Hours
class SmoothVenueEditorDialog extends StatefulWidget {
  final Venue? initialVenue;
  final VenueType initialType;
  final bool isArabic;
  final bool populateDefaults;
  final ValueChanged<Venue> onSaved;

  const SmoothVenueEditorDialog({
    super.key,
    this.initialVenue,
    this.initialType = VenueType.sports,
    this.isArabic = false,
    this.populateDefaults = false,
    required this.onSaved,
  });

  @override
  State<SmoothVenueEditorDialog> createState() => _SmoothVenueEditorDialogState();
}

class _SmoothVenueEditorDialogState extends State<SmoothVenueEditorDialog> {
  // Controllers
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _depositPercentController = TextEditingController();
  final _vodafoneCashController = TextEditingController();
  final _instaPayController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _googleMapsController = TextEditingController();

  late VenueType _selectedType;
  int _openHour = 10;
  int _closeHour = 24;
  final List<String> _selectedAmenities = [];

  // Rooms / Units / Chairs
  late List<_EditableItem> _items = [];

  // Salon Services / Add-ons
  late List<_EditableService> _services = [];

  static const List<Map<String, String>> _photoPresets = [
    {
      'label': '🎾 Padel Court',
      'url': 'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'label': '⚽ Football Pitch',
      'url': 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'label': '💈 Luxury Salon Chair',
      'url': 'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'label': '🎮 PS5 & OLED VIP Lounge',
      'url': 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'label': '💼 Co-Working Space',
      'url': 'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'label': '🎱 Billiards & Snooker',
      'url': 'https://images.unsplash.com/photo-1588731234159-8b9963143fca?auto=format&fit=crop&w=1200&q=80',
    },
  ];

  static const List<String> _allAmenities = [
    'Wi-Fi',
    'Air Conditioning',
    'Parking',
    'Night Floodlights',
    'Showers',
    'Cafeteria',
    'Prayer Room',
    'PlayStation 5',
    'Waiting Lounge',
    'Lockers',
  ];

  static const List<String> _egyptianCities = [
    'New Cairo',
    'Sheikh Zayed',
    '6th of October',
    'Maadi',
    'Nasr City',
    'Heliopolis',
    'Zamalek',
    'Giza',
    'Alexandria',
    'Mansoura',
    'Tanta',
    'Kafr El Sheikh',
  ];

  bool get isSalon => _selectedType == VenueType.salon;
  bool get isEscapeRoom =>
      widget.initialVenue?.subCategories.contains('escape_rooms') == true ||
      _selectedAmenities.any((a) => a.contains('إسكيب') || a.toLowerCase().contains('escape')) ||
      widget.initialVenue?.name.toLowerCase().contains('escape') == true ||
      _nameController.text.toLowerCase().contains('escape') ||
      _items.any((i) =>
          i.kind.toLowerCase().contains('escape') ||
          i.name.contains('دار الأيتام') ||
          i.name.contains('آكلي لحوم البشر') ||
          i.name.contains('اللعنة'));

  @override
  void initState() {
    super.initState();
    final v = widget.initialVenue;

    if (v != null) {
      _selectedType = v.type;
      _nameController.text = v.name;
      _addressController.text = v.location;
      _ownerPhoneController.text = v.ownerPhone;
      _depositPercentController.text = v.depositPercent.toStringAsFixed(0);
      _vodafoneCashController.text = v.vodafoneCashNumber;
      _instaPayController.text = v.instaPayAddress;
      _ownerEmailController.text = v.ownerEmail;
      _imageUrlController.text = v.imageUrl ?? '';
      _descriptionController.text = v.description;
      _googleMapsController.text = v.googleMapsUrl;
      _openHour = v.openHour;
      _closeHour = v.closeHour;
      _selectedAmenities.addAll(v.amenities);

      _items = v.items.map((i) => _EditableItem(
        id: i.id,
        name: i.name,
        kind: i.kind,
        hourlyRate: i.hourlyRate,
        peakRate: (i.multiRate > 0 && i.multiRate != i.hourlyRate) ? i.multiRate : i.hourlyRate,
        description: i.description,
        imageUrl: i.imageUrl,
        pricingMode: i.pricingMode,
        pricingTiers: i.pricingTiers,
        minCapacity: i.minCapacity,
        maxCapacity: i.maxCapacity,
      )).toList();

      _services = v.services.map((s) => _EditableService(
        id: s.id,
        name: s.name,
        price: s.price,
        minutes: s.minutes,
      )).toList();
    } else {
      _selectedType = widget.initialType;
      _nameController.text = '';
      _addressController.text = 'New Cairo';
      _ownerPhoneController.text = '01015325250';
      _depositPercentController.text = '25';
      _openHour = 10;
      _closeHour = 24;
      _selectedAmenities.addAll(['Wi-Fi', 'Air Conditioning', 'Parking']);
      if (widget.populateDefaults) {
        _populateDefaultItemsForType(_selectedType);
      }
    }
  }

  void _populateDefaultItemsForType(VenueType type) {
    _items.clear();
    _services.clear();
    if (type == VenueType.salon) {
      _items.addAll([
        _EditableItem(
          id: 'chair_1',
          name: 'Master Barber Chair 1',
          kind: 'Master Station',
          hourlyRate: 150,
          peakRate: 200,
          description: 'Hydraulic barber chair with hot towel station.',
          imageUrl: 'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=800&q=80',
        ),
        _EditableItem(
          id: 'chair_2',
          name: 'Styling Chair 2',
          kind: 'Standard',
          hourlyRate: 120,
          peakRate: 150,
          description: 'Ergonomic styling station with mirror lighting.',
          imageUrl: 'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?auto=format&fit=crop&w=800&q=80',
        ),
        _EditableItem(
          id: 'chair_vip',
          name: 'VIP Private Grooming Suite',
          kind: 'VIP Suite',
          hourlyRate: 250,
          peakRate: 300,
          description: 'Private enclosed suite with recliner & beverage bar.',
          imageUrl: 'https://images.unsplash.com/photo-1599351431202-1e0f0137899a?auto=format&fit=crop&w=800&q=80',
        ),
      ]);
      _services.addAll([
        _EditableService(id: 'svc_hair', name: 'Haircut & Styling', price: 100, minutes: 30),
        _EditableService(id: 'svc_beard', name: 'Hot Towel Beard Grooming', price: 70, minutes: 20),
        _EditableService(id: 'svc_vip', name: 'VIP Total Grooming Package', price: 250, minutes: 60),
      ]);
    } else if (type == VenueType.lounge) {
      _items.addAll([
        _EditableItem(
          id: 'ps_room_1',
          name: 'PS5 Room 1 (65" 4K OLED)',
          kind: 'VIP Lounge',
          hourlyRate: 80,
          peakRate: 100,
          description: 'Private soundproof room, 65" LG OLED, 4 DualSense controllers.',
          imageUrl: 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?auto=format&fit=crop&w=800&q=80',
        ),
        _EditableItem(
          id: 'ps_room_2',
          name: 'PS5 Room 2 (Standard)',
          kind: 'Standard Room',
          hourlyRate: 60,
          peakRate: 80,
          description: 'Cozy gaming setup with 55" 4K HDR TV and leather seating.',
          imageUrl: 'https://images.unsplash.com/photo-1511512578047-dfb367046420?auto=format&fit=crop&w=800&q=80',
        ),
        _EditableItem(
          id: 'billiard_1',
          name: 'Tournament Billiards Table',
          kind: 'Billiards',
          hourlyRate: 70,
          peakRate: 90,
          description: '9-foot tournament slate pool table with premium cues.',
          imageUrl: 'https://images.unsplash.com/photo-1588731234159-8b9963143fca?auto=format&fit=crop&w=800&q=80',
        ),
      ]);
    } else {
      _items.addAll([
        _EditableItem(
          id: 'court_1',
          name: 'Court 1 (Panoramic Glass)',
          kind: 'Panoramic',
          hourlyRate: 400,
          peakRate: 500,
          description: 'Panoramic glass court with LED floodlights and blue Mondo turf.',
          imageUrl: 'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?auto=format&fit=crop&w=800&q=80',
        ),
        _EditableItem(
          id: 'court_2',
          name: 'Court 2 (Standard)',
          kind: 'Standard',
          hourlyRate: 350,
          peakRate: 450,
          description: 'Standard outdoor court with high-visibility lighting.',
          imageUrl: 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=800&q=80',
        ),
      ]);
      _services.addAll([
        _EditableService(id: 'svc_racket', name: 'Pro Racket Rental', price: 50, minutes: 60),
        _EditableService(id: 'svc_balls', name: 'New Ball Canister (3 balls)', price: 180, minutes: 60),
      ]);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _ownerPhoneController.dispose();
    _depositPercentController.dispose();
    _vodafoneCashController.dispose();
    _instaPayController.dispose();
    _ownerEmailController.dispose();
    _imageUrlController.dispose();
    _descriptionController.dispose();
    _googleMapsController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFile() async {
    try {
      final dataUrl = await ImageUploadService.pickImage();
      if (dataUrl != null && dataUrl.isNotEmpty && mounted) {
        setState(() {
          _imageUrlController.text = dataUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isArabic ? 'تم تحميل ملف الصورة بنجاح!' : 'Image file selected successfully!',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load image: $e')),
        );
      }
    }
  }

  void _saveVenue() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isArabic ? 'يرجى كتابة اسم المكان' : 'Please enter venue name'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final dep = double.tryParse(_depositPercentController.text.trim()) ?? 25.0;
    final venueId = widget.initialVenue?.id ?? 'v_${DateTime.now().millisecondsSinceEpoch}';

    final items = _items.map((i) => VenueItem(
      id: i.id.isNotEmpty ? i.id : 'item_${DateTime.now().microsecondsSinceEpoch}',
      name: i.name.trim(),
      kind: i.kind.trim(),
      hourlyRate: i.hourlyRate,
      multiRate: (i.peakRate > 0 && i.peakRate != i.hourlyRate) ? i.peakRate : 0.0,
      description: i.description.trim(),
      imageUrl: i.imageUrl?.trim().isNotEmpty == true ? i.imageUrl!.trim() : null,
      pricingMode: i.pricingMode,
      pricingTiers: i.pricingTiers,
      minCapacity: i.minCapacity,
      maxCapacity: i.maxCapacity,
    )).toList();

    final services = _services.map((s) => SalonService(
      id: s.id.isNotEmpty ? s.id : 'svc_${DateTime.now().microsecondsSinceEpoch}',
      name: s.name.trim(),
      price: s.price,
      minutes: s.minutes,
    )).toList();

    final venue = Venue(
      id: venueId,
      name: name,
      location: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : 'Cairo, Egypt',
      type: _selectedType,
      depositPercent: dep.clamp(0.0, 100.0),
      imageUrl: _imageUrlController.text.trim().isNotEmpty ? _imageUrlController.text.trim() : null,
      description: _descriptionController.text.trim(),
      googleMapsUrl: _googleMapsController.text.trim(),
      instaPayAddress: _instaPayController.text.trim(),
      vodafoneCashNumber: _vodafoneCashController.text.trim(),
      ownerEmail: _ownerEmailController.text.trim().toLowerCase(),
      ownerPhone: _ownerPhoneController.text.trim(),
      openHour: _openHour,
      closeHour: _closeHour > _openHour ? _closeHour : 24,
      amenities: List.from(_selectedAmenities),
      items: items,
      services: services,
    );

    widget.onSaved(venue);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isArabic;
    final isEditing = widget.initialVenue != null;
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final dialogBg = isDark ? const Color(0xFF111B17) : Colors.white;
    final cardBg = isDark ? const Color(0xFF162822) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF162822) : Colors.grey.shade50;
    final borderColor = isDark ? const Color(0xFF1F352D) : Colors.grey.shade200;
    final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Scaffold(
          backgroundColor: dialogBg,
          appBar: AppBar(
            backgroundColor: dialogBg,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: textColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              isEditing
                  ? (isAr ? 'تعديل وتحديث المكان' : 'Renovate / Edit Venue')
                  : (isAr ? 'إضافة مكان جديد' : 'Add a venue'),
              style: TextStyle(
                color: textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // SECTION 1: Category & Basic Details
                _buildSectionHeader(
                  icon: Icons.storefront_rounded,
                  title: isAr ? 'البيانات الأساسية ونوع المكان' : 'Basic Info & Category',
                  textColor: textColor,
                ),
                const SizedBox(height: 10),
                SegmentedButton<VenueType>(
                  segments: [
                    ButtonSegment(
                      value: VenueType.sports,
                      label: Text(isAr ? 'ملاعب ورياضة' : 'Sports & Courts'),
                      icon: const Icon(Icons.sports_tennis_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: VenueType.salon,
                      label: Text(isAr ? 'صالون ورعاية' : 'Salon & Barber'),
                      icon: const Icon(Icons.content_cut_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: VenueType.lounge,
                      label: Text(isAr ? 'صالة ألعاب ولونج' : 'Gaming & Lounge'),
                      icon: const Icon(Icons.sports_esports_rounded, size: 18),
                    ),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedType = val.first;
                      if (widget.initialVenue == null) {
                        _populateDefaultItemsForType(_selectedType);
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
                // Field 0: Venue name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: isAr ? 'اسم المكان *' : 'Venue Name *',
                    hintText: _selectedType == VenueType.salon
                        ? 'e.g. Master Barber & VIP Lounge'
                        : _selectedType == VenueType.lounge
                            ? 'e.g. Matrix Gaming Lounge & PS5'
                            : 'e.g. Nile Padel Club',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.storefront_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                // Field 1: Area / Location
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: isAr ? 'المدينة والمنطقة بالتفصيل *' : 'City, Area & Detailed Address *',
                    hintText: 'e.g. 5th Settlement, New Cairo',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _egyptianCities.map((city) {
                    return ActionChip(
                      backgroundColor: isDark ? const Color(0xFF162822) : null,
                      side: BorderSide(color: isDark ? const Color(0xFF1F352D) : Colors.grey.shade300),
                      label: Text(
                        city,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _addressController.text = '$city, Egypt';
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // Field 2: Owner Contact Phone
                TextFormField(
                  controller: _ownerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isAr ? 'رقم هاتف المالك *' : 'Owner Contact Phone *',
                    hintText: '01015325250',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                // Field 3: Deposit policy %
                TextFormField(
                  controller: _depositPercentController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isAr ? 'نسبة العربون المطلوب من العميل (%) *' : 'Required Deposit Policy (%) *',
                    hintText: '25',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.percent_rounded),
                    helperText: isAr
                        ? 'النسبة المعتادة في مصر تتراوح بين 15% و 50%'
                        : 'Typical Egyptian deposit policy is 15% to 50%',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [15, 20, 25, 30, 50].map((percent) {
                    return ActionChip(
                      backgroundColor: isDark ? const Color(0xFF162822) : null,
                      side: BorderSide(color: isDark ? const Color(0xFF1F352D) : Colors.grey.shade300),
                      label: Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _depositPercentController.text = percent.toString();
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                Divider(color: borderColor),
                const SizedBox(height: 12),

                // SECTION 2: Rooms, Courts & Salon Chairs with Time-Based Pricing
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _buildSectionHeader(
                        icon: Icons.meeting_room_rounded,
                        title: _selectedType == VenueType.salon
                            ? (isAr ? 'كراسي الحلاقة ومحطات الخدمة' : 'Salon Chairs & Stations')
                            : (isAr ? 'الغرف، الملاعب والوحدات' : 'Rooms, Courts & Units'),
                        textColor: textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _showAddItemDialog(isAr),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(
                        _selectedType == VenueType.salon
                            ? (isAr ? '+ كرسي جديد' : '+ Add Chair')
                            : (isAr ? '+ غرفة / ملعب' : '+ Add Room'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? 'حدد سعر الساعة العادي وسعر وقت الذروة / المساء لكل وحدة على حدة.'
                      : 'Set regular and peak time-based hourly rates for each room, court, or chair.',
                  style: TextStyle(color: mutedColor, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surfaceBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Center(
                      child: Text(
                        _selectedType == VenueType.salon
                            ? (isAr ? 'لم تتم إضافة أي كراسي' : 'No chairs added yet')
                            : (isAr ? 'لم تتم إضافة أي غرف' : 'No rooms added yet'),
                        style: TextStyle(fontWeight: FontWeight.w600, color: mutedColor),
                      ),
                    ),
                  )
                else
                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                                ? HagzySmartImage(
                                    imageUrl: item.imageUrl!,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorWidget: Container(
                                      width: 44,
                                      height: 44,
                                      color: isDark ? const Color(0xFF1E3A2F) : kSurfaceTint,
                                      child: Icon(
                                        _selectedType == VenueType.salon ? Icons.chair_rounded : Icons.sports_tennis_rounded,
                                        color: isDark ? kGreenLight : kGreen,
                                        size: 20,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E3A2F) : kSurfaceTint,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _selectedType == VenueType.salon ? Icons.chair_rounded : Icons.sports_tennis_rounded,
                                      color: isDark ? kGreenLight : kGreen,
                                      size: 20,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textColor),
                                ),
                                 if (item.description.isNotEmpty) ...[
                                   const SizedBox(height: 4),
                                   Text(
                                     item.description,
                                     maxLines: 5,
                                     overflow: TextOverflow.ellipsis,
                                     style: TextStyle(
                                       fontSize: 13,
                                       height: 1.45,
                                       color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                                     ),
                                   ),
                                 ],
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1F352D) : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.kind,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      isEscapeRoom
                                          ? (isAr ? '${item.hourlyRate.toStringAsFixed(0)} ج.م / فرد' : '${item.hourlyRate.toStringAsFixed(0)} EGP / person')
                                          : (isSalon
                                              ? (isAr ? '${item.hourlyRate.toStringAsFixed(0)} ج.م' : '${item.hourlyRate.toStringAsFixed(0)} EGP')
                                              : (isAr ? '${item.hourlyRate.toStringAsFixed(0)} ج.م/ساعة' : '${item.hourlyRate.toStringAsFixed(0)} EGP/hr')),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? kGreenLight : kGreen,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (item.peakRate > 0 && item.peakRate != item.hourlyRate)
                                      Text(
                                        '• Peak: ${item.peakRate.toStringAsFixed(0)} EGP',
                                        style: TextStyle(fontSize: 11.5, color: mutedColor),
                                      ),
                                    if (item.pricingTiers != null && item.pricingTiers!.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      ...item.pricingTiers!.entries.map((e) => Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isDark ? kGreenLight : kGreen).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          isAr ? '≤${e.key} أفراد: ${e.value} ج' : '≤${e.key}p: ${e.value}EGP',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? kGreenLight : kGreenDark,
                                          ),
                                        ),
                                      )),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit_outlined, size: 18, color: textColor),
                            onPressed: () => _showEditItemDialog(item, idx, isAr),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                            onPressed: () => setState(() => _items.removeAt(idx)),
                          ),
                        ],
                      ),
                    );
                  }),

                // SECTION 3: Services (for Salon or Sports)
                const SizedBox(height: 20),
                Divider(color: borderColor),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _buildSectionHeader(
                        icon: Icons.content_cut_rounded,
                        title: _selectedType == VenueType.salon
                            ? (isAr ? 'خدمات الصالون وباقاته' : 'Salon Services & Packages')
                            : (isAr ? 'الخدمات الإضافية والتأجير' : 'Add-ons & Equipment Rental'),
                        textColor: textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showAddServiceDialog(isAr),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(isAr ? '+ إضافة خدمة' : '+ Add Service'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_services.isEmpty)
                  Text(
                    isAr ? 'لا توجد خدمات إضافية.' : 'No additional services configured.',
                    style: TextStyle(color: mutedColor, fontSize: 12.5),
                  )
                else
                  ..._services.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final svc = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: kGreen),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${svc.name} (${svc.minutes} min)',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor),
                            ),
                          ),
                          Text(
                            '${svc.price.toStringAsFixed(0)} EGP',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: kGreen, fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.close_rounded, size: 16, color: mutedColor),
                            onPressed: () => setState(() => _services.removeAt(idx)),
                          ),
                        ],
                      ),
                    );
                  }),

                // SECTION 4: Photos & Amenities
                const SizedBox(height: 20),
                Divider(color: borderColor),
                const SizedBox(height: 12),
                _buildSectionHeader(
                  icon: Icons.add_photo_alternate_rounded,
                  title: isAr ? 'صور المكان والمميزات' : 'Pictures & Amenities',
                  textColor: textColor,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _pickImageFile,
                        icon: const Icon(Icons.file_upload_outlined, size: 20),
                        label: Text(
                          isAr ? 'رفع صورة من جهازك (ملف)' : 'Upload Picture File',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                    if (_imageUrlController.text.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: isAr ? 'مسح الصورة' : 'Clear Image',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _imageUrlController.clear()),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _imageUrlController,
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: isAr ? 'أو أدخل رابط صورة الغلاف (URL)' : 'Or enter Cover Picture URL',
                    hintText: 'https://images.unsplash.com/...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.link_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _photoPresets.map((preset) {
                    return ChoiceChip(
                      backgroundColor: isDark ? const Color(0xFF162822) : null,
                      selectedColor: isDark ? const Color(0xFF1E3A2F) : kSurfaceTint,
                      side: BorderSide(color: isDark ? const Color(0xFF1F352D) : Colors.grey.shade300),
                      label: Text(
                        preset['label']!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: _imageUrlController.text.trim() == preset['url'],
                      onSelected: (_) {
                        setState(() {
                          _imageUrlController.text = preset['url']!;
                        });
                      },
                    );
                  }).toList(),
                ),
                if (_imageUrlController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border.all(color: borderColor),
                      ),
                      child: HagzySmartImage(
                        imageUrl: _imageUrlController.text.trim(),
                        fit: BoxFit.cover,
                        errorWidget: Center(
                          child: Text(
                            isAr ? 'تعذر معاينة الصورة' : 'Could not preview image',
                            style: TextStyle(fontSize: 12, color: mutedColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  isAr ? 'تجهيزات ومميزات المكان:' : 'Available Amenities:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textColor),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allAmenities.map((amenity) {
                    final selected = _selectedAmenities.contains(amenity);
                    return FilterChip(
                      backgroundColor: isDark ? const Color(0xFF162822) : null,
                      selectedColor: isDark ? const Color(0xFF1E3A2F) : kSurfaceTint,
                      side: BorderSide(color: isDark ? const Color(0xFF1F352D) : Colors.grey.shade300),
                      label: Text(
                        amenity,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      selected: selected,
                      checkmarkColor: kGreen,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedAmenities.add(amenity);
                          } else {
                            _selectedAmenities.remove(amenity);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),

                // SECTION 5: Payouts & Working Hours
                const SizedBox(height: 20),
                Divider(color: borderColor),
                const SizedBox(height: 12),
                _buildSectionHeader(
                  icon: Icons.account_balance_wallet_rounded,
                  title: isAr ? 'طرق الدفع ومواعيد العمل' : 'Payout Accounts & Hours',
                  textColor: textColor,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _vodafoneCashController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isAr ? 'رقم المحفظة الإلكترونية (فودافون كاش)' : 'Mobile Wallet (Vodafone Cash)',
                    hintText: '01015325250',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instaPayController,
                  decoration: InputDecoration(
                    labelText: isAr ? 'عنوان إنستاباي (InstaPay Handle)' : 'InstaPay Handle',
                    hintText: 'venue@instapay',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ownerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: isAr ? 'البريد الإلكتروني للإدارة' : 'Owner Email Address',
                    hintText: 'owner@venue.com',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: isAr ? 'نبذة عن المكان (اختياري)' : 'Description (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _openHour,
                        dropdownColor: isDark ? const Color(0xFF162822) : Colors.white,
                        style: TextStyle(color: textColor, fontSize: 13.5),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: isAr ? 'ساعة الفتح' : 'Opening Time',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.schedule_rounded),
                        ),
                        items: List.generate(24, (i) => i).map((h) {
                          final display = h == 0
                              ? '12:00 AM'
                              : h < 12
                                  ? '$h:00 AM'
                                  : h == 12
                                      ? '12:00 PM'
                                      : '${h - 12}:00 PM';
                          return DropdownMenuItem(
                            value: h,
                            child: Text(display, style: TextStyle(color: textColor), overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _openHour = val ?? 10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _closeHour,
                        dropdownColor: isDark ? const Color(0xFF162822) : Colors.white,
                        style: TextStyle(color: textColor, fontSize: 13.5),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: isAr ? 'ساعة الإغلاق' : 'Closing Time',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.nightlight_round),
                        ),
                        items: List.generate(25, (i) => i).map((h) {
                          final display = h == 24 || h == 0
                              ? '12:00 AM'
                              : h < 12
                                  ? '$h:00 AM'
                                  : h == 12
                                      ? '12:00 PM'
                                      : '${h - 12}:00 PM';
                          return DropdownMenuItem(
                            value: h,
                            child: Text(display, style: TextStyle(color: textColor), overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _closeHour = val ?? 24),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: dialogBg,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    isAr ? 'إلغاء' : 'Cancel',
                    style: TextStyle(color: mutedColor, fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saveVenue,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    isEditing
                        ? (isAr ? 'حفظ التعديلات' : 'Save Changes')
                        : (isAr ? 'إضافة مكان' : 'Add venue'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title, Color? textColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: kGreen),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textColor ?? kInk),
          ),
        ),
      ],
    );
  }

  // DIALOG: Add Item (Room / Chair)
  void _showAddItemDialog(bool isAr) {
    final isSalon = _selectedType == VenueType.salon;
    final isEscape = isEscapeRoom;
    final nameCtrl = TextEditingController(
      text: isSalon ? 'Chair ${_items.length + 1}' : (isEscape ? 'Room ${_items.length + 1}' : 'Court ${_items.length + 1}'),
    );
    final kindCtrl = TextEditingController(text: isSalon ? 'Standard Station' : (isEscape ? 'Escape Room' : 'Standard'));
    final rateCtrl = TextEditingController(text: isSalon ? '150' : (isEscape ? '150' : '350'));
    final peakCtrl = TextEditingController(text: isSalon ? '150' : (isEscape ? '150' : '450'));
    final minCapCtrl = TextEditingController(text: isEscape ? '2' : '1');
    final maxCapCtrl = TextEditingController(text: isEscape ? '15' : '10');
    final descCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    bool enablePeakPricing = false;
    bool isTiered = isEscape;
    final editableTiers = <MapEntry<TextEditingController, TextEditingController>>[
      if (isEscape) ...[
        MapEntry(TextEditingController(text: '3'), TextEditingController(text: '150')),
        MapEntry(TextEditingController(text: '5'), TextEditingController(text: '120')),
        MapEntry(TextEditingController(text: '15'), TextEditingController(text: '100')),
      ],
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF111B17) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF162822) : Colors.grey.shade100;
          final borderColor = isDark ? const Color(0xFF1F352D) : Colors.grey.shade300;
          final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
          final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          Future<void> pickUnitImage() async {
            try {
              final dataUrl = await ImageUploadService.pickImage();
              if (dataUrl != null && dataUrl.isNotEmpty) {
                setDialogState(() {
                  imageCtrl.text = dataUrl;
                });
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to load image: $e')),
                );
              }
            }
          }

          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            ),
            title: Text(
              isSalon
                  ? (isAr ? 'إضافة كرسي حلاقة جديد' : 'Add New Salon Chair')
                  : (isAr ? 'إضافة غرفة أو ملعب جديد' : 'Add New Room or Court'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textColor),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: isSalon ? 'اسم الكرسي / المحطة *' : 'اسم الغرفة / الملعب *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: kindCtrl,
                      decoration: InputDecoration(
                        labelText: 'النوع / الفئة (Standard, VIP, Panoramic...)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!enablePeakPricing) ...[
                      TextFormField(
                        controller: rateCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isEscape
                              ? (isAr ? 'سعر الفرد (جنيه) *' : 'Rate per Person (EGP) *')
                              : (isSalon
                                  ? (isAr ? 'السعر (جنيه) *' : 'Price (EGP) *')
                                  : (isAr ? 'السعر (جنيه) *' : 'Rate (EGP) *')),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () {
                          setDialogState(() {
                            enablePeakPricing = true;
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline_rounded, size: 16, color: kGreen),
                              const SizedBox(width: 6),
                              Text(
                                isAr ? 'تفعيل سعر ذروة مختلف (إذا كان المكان يطبق أسعار ذروة)' : 'Add different Peak / Surge Rate',
                                style: const TextStyle(fontSize: 12, color: kGreen, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: rateCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: isAr ? 'السعر العادي (جنيه)' : 'Regular Rate (EGP)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: peakCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: isAr ? 'سعر الذروة (جنيه)' : 'Peak Rate (EGP)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () {
                            setDialogState(() {
                              enablePeakPricing = false;
                              peakCtrl.text = rateCtrl.text;
                            });
                          },
                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 14),
                          label: Text(
                            isAr ? 'إلغاء سعر الذروة (سعر ثابت)' : 'Disable peak rate (Fixed rate)',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'وصف الغرفة أو التجهيزات (اختياري)' : 'Description & Features (Optional)',
                        hintText: isSalon
                            ? 'e.g. VIP reclining chair, hot towel service'
                            : 'e.g. 4K OLED, 2 wireless controllers, sound system',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minCapCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isAr ? 'أقل عدد أفراد (Min)' : 'Min Players',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: maxCapCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isAr ? 'أقصى عدد أفراد (Max)' : 'Max Players',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isAr ? 'أسعار متدرجة حسب عدد الأفراد (Tiered Group Pricing)' : 'Tiered Pricing by Group Size',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      subtitle: Text(
                        isAr ? 'يقل سعر الفرد مع زيادة حجم المجموعة (مناسب للغرف واللاونج)' : 'Per-person rate drops as headcount increases',
                        style: TextStyle(fontSize: 11.5, color: mutedColor),
                      ),
                      value: isTiered,
                      onChanged: (val) {
                        setDialogState(() {
                          isTiered = val ?? false;
                          if (isTiered && editableTiers.isEmpty) {
                            editableTiers.addAll([
                              MapEntry(TextEditingController(text: '3'), TextEditingController(text: '150')),
                              MapEntry(TextEditingController(text: '5'), TextEditingController(text: '120')),
                              MapEntry(TextEditingController(text: '15'), TextEditingController(text: '100')),
                            ]);
                          }
                        });
                      },
                    ),
                    if (isTiered) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: surfaceBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              isAr ? 'شرائح الأسعار (حسب حجم المجموعة):' : 'Group Pricing Tiers Ladder:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textColor),
                            ),
                            const SizedBox(height: 8),
                            for (int ti = 0; ti < editableTiers.length; ti++) ...[
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: editableTiers[ti].key,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: isAr ? 'حتى عدد' : 'Up to people',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: TextFormField(
                                      controller: editableTiers[ti].value,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: isAr ? 'سعر الفرد (جنيه)' : 'EGP / person',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                    onPressed: () {
                                      setDialogState(() => editableTiers.removeAt(ti));
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            Align(
                              alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    final nextCap = (editableTiers.length + 1) * 3;
                                    editableTiers.add(MapEntry(
                                      TextEditingController(text: nextCap.toString()),
                                      TextEditingController(text: '100'),
                                    ));
                                  });
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: Text(isAr ? '+ إضافة شريحة سعر جديدة' : '+ Add Pricing Tier'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: pickUnitImage,
                            icon: const Icon(Icons.file_upload_outlined, size: 18),
                            label: Text(
                              isSalon
                                  ? (isAr ? 'رفع صورة الكرسي (ملف)' : 'Upload Chair Picture')
                                  : (isAr ? 'رفع صورة الغرفة / الملعب (ملف)' : 'Upload Room Picture'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                        ),
                        if (imageCtrl.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: isAr ? 'مسح الصورة' : 'Clear Image',
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () => setDialogState(() => imageCtrl.clear()),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: imageCtrl,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: isAr ? 'أو رابط صورة الوحدة (URL)' : 'Or Unit Picture URL',
                        hintText: 'https://images.unsplash.com/...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.link_rounded, size: 18),
                      ),
                    ),
                    if (imageCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: surfaceBg,
                            border: Border.all(color: borderColor),
                          ),
                          child: HagzySmartImage(
                            imageUrl: imageCtrl.text.trim(),
                            fit: BoxFit.cover,
                            errorWidget: Center(
                              child: Text(
                                isAr ? 'تعذر معاينة الصورة' : 'Could not preview image',
                                style: TextStyle(fontSize: 11, color: mutedColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  isAr ? 'إلغاء' : 'Cancel',
                  style: TextStyle(color: mutedColor, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGreen),
                onPressed: () {
                  final n = nameCtrl.text.trim();
                  if (n.isEmpty) return;
                  final r = double.tryParse(rateCtrl.text.trim()) ?? 150.0;
                  final p = enablePeakPricing ? (double.tryParse(peakCtrl.text.trim()) ?? r) : r;

                  Map<String, dynamic>? resolvedTiers;
                  if (isTiered && editableTiers.isNotEmpty) {
                    resolvedTiers = {};
                    for (final t in editableTiers) {
                      final cap = t.key.text.trim();
                      final price = double.tryParse(t.value.text.trim()) ?? 0.0;
                      if (cap.isNotEmpty && price > 0) {
                        resolvedTiers[cap] = price;
                      }
                    }
                  }
                  final minCap = int.tryParse(minCapCtrl.text.trim()) ?? (isTiered ? 2 : 1);
                  final maxCap = int.tryParse(maxCapCtrl.text.trim()) ?? (isTiered ? 15 : 10);

                  setState(() {
                    _items.add(_EditableItem(
                      id: 'unit_${DateTime.now().microsecondsSinceEpoch}',
                      name: n,
                      kind: kindCtrl.text.trim().isNotEmpty ? kindCtrl.text.trim() : (isEscape ? 'Escape Room' : 'Standard'),
                      hourlyRate: r,
                      peakRate: p,
                      description: descCtrl.text.trim(),
                      imageUrl: imageCtrl.text.trim().isNotEmpty ? imageCtrl.text.trim() : null,
                      pricingMode: isTiered ? 'per_person_tiered' : null,
                      pricingTiers: resolvedTiers,
                      minCapacity: minCap,
                      maxCapacity: maxCap,
                    ));
                  });
                  Navigator.pop(ctx);
                },
                child: Text(isAr ? 'إضافة' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  // DIALOG: Edit Item
  void _showEditItemDialog(_EditableItem item, int idx, bool isAr) {
    final nameCtrl = TextEditingController(text: item.name);
    final kindCtrl = TextEditingController(text: item.kind);
    final isSalon = _selectedType == VenueType.salon;
    final isEscape = isEscapeRoom;
    final rateCtrl = TextEditingController(text: item.hourlyRate.toStringAsFixed(0));
    final peakCtrl = TextEditingController(text: item.peakRate.toStringAsFixed(0));
    final minCapCtrl = TextEditingController(text: item.minCapacity != null ? item.minCapacity.toString() : (isEscape ? '2' : '1'));
    final maxCapCtrl = TextEditingController(text: item.maxCapacity != null ? item.maxCapacity.toString() : (isEscape ? '15' : '10'));
    final descCtrl = TextEditingController(text: item.description);
    final imageCtrl = TextEditingController(text: item.imageUrl ?? '');
    final bool initialHasPeak = item.peakRate > 0 && item.peakRate != item.hourlyRate;
    bool enablePeakPricing = initialHasPeak;
    final editableTiers = <MapEntry<TextEditingController, TextEditingController>>[];
    if (item.pricingTiers != null && item.pricingTiers!.isNotEmpty) {
      for (final entry in item.pricingTiers!.entries) {
        editableTiers.add(MapEntry(
          TextEditingController(text: entry.key),
          TextEditingController(text: (entry.value as num).toStringAsFixed(0)),
        ));
      }
    }
    bool isTiered = item.pricingMode == 'per_person_tiered' || editableTiers.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
          final dialogBg = isDark ? const Color(0xFF111B17) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF162822) : Colors.grey.shade100;
          final borderColor = isDark ? const Color(0xFF1F352D) : Colors.grey.shade300;
          final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
          final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          Future<void> pickUnitImage() async {
            try {
              final dataUrl = await ImageUploadService.pickImage();
              if (dataUrl != null && dataUrl.isNotEmpty) {
                setDialogState(() {
                  imageCtrl.text = dataUrl;
                });
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to load image: $e')),
                );
              }
            }
          }

          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            ),
            title: Text(
              isAr ? 'تعديل تفاصيل الوحدة والأسعار' : 'Edit Room / Chair & Rates',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textColor),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'الاسم *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: kindCtrl,
                      decoration: InputDecoration(
                        labelText: 'الفئة / النوع',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!enablePeakPricing) ...[
                      TextFormField(
                        controller: rateCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: isEscape
                              ? (isAr ? 'سعر الفرد (جنيه) *' : 'Rate per Person (EGP) *')
                              : (isSalon
                                  ? (isAr ? 'السعر (جنيه) *' : 'Price (EGP) *')
                                  : (isAr ? 'السعر (جنيه) *' : 'Rate (EGP) *')),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () {
                          setDialogState(() {
                            enablePeakPricing = true;
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline_rounded, size: 16, color: kGreen),
                              const SizedBox(width: 6),
                              Text(
                                isAr ? 'تفعيل سعر ذروة مختلف (إذا كان المكان يطبق أسعار ذروة)' : 'Add different Peak / Surge Rate',
                                style: const TextStyle(fontSize: 12, color: kGreen, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: rateCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: isAr ? 'السعر العادي (جنيه)' : 'Regular Rate (EGP)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: peakCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: isAr ? 'سعر الذروة (جنيه)' : 'Peak Rate (EGP)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () {
                            setDialogState(() {
                              enablePeakPricing = false;
                              peakCtrl.text = rateCtrl.text;
                            });
                          },
                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 14),
                          label: Text(
                            isAr ? 'إلغاء سعر الذروة (سعر ثابت)' : 'Disable peak rate (Fixed rate)',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                    if (item.pricingTiers != null && item.pricingTiers!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: surfaceBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? '💰 أسعار المجموعات / حسب عدد الأفراد (ثابتة بدون ذروة):' : '💰 Tiered Pricing by Group Size (Flat / No Peak):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor),
                            ),
                            const SizedBox(height: 6),
                            ...item.pricingTiers!.entries.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                isAr ? '• حتى ${e.key} أفراد: ${e.value} جنيه للفرد' : '• Up to ${e.key} players: ${e.value} EGP / person',
                                style: TextStyle(fontSize: 11.5, color: mutedColor),
                              ),
                            )),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: isAr ? 'وصف الغرفة أو التجهيزات (اختياري)' : 'Description & Features (Optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minCapCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isAr ? 'أقل عدد أفراد (Min)' : 'Min Players',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: maxCapCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: isAr ? 'أقصى عدد أفراد (Max)' : 'Max Players',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isAr ? 'أسعار متدرجة حسب عدد الأفراد (Tiered Group Pricing)' : 'Tiered Pricing by Group Size',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      subtitle: Text(
                        isAr ? 'يقل سعر الفرد مع زيادة حجم المجموعة (مناسب للغرف واللاونج)' : 'Per-person rate drops as headcount increases',
                        style: TextStyle(fontSize: 11.5, color: mutedColor),
                      ),
                      value: isTiered,
                      onChanged: (val) {
                        setDialogState(() {
                          isTiered = val ?? false;
                          if (isTiered && editableTiers.isEmpty) {
                            editableTiers.addAll([
                              MapEntry(TextEditingController(text: '3'), TextEditingController(text: '150')),
                              MapEntry(TextEditingController(text: '5'), TextEditingController(text: '120')),
                              MapEntry(TextEditingController(text: '15'), TextEditingController(text: '100')),
                            ]);
                          }
                        });
                      },
                    ),
                    if (isTiered) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: surfaceBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              isAr ? 'شرائح الأسعار (حسب حجم المجموعة):' : 'Group Pricing Tiers Ladder:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textColor),
                            ),
                            const SizedBox(height: 8),
                            for (int ti = 0; ti < editableTiers.length; ti++) ...[
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: editableTiers[ti].key,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: isAr ? 'حتى عدد' : 'Up to people',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: TextFormField(
                                      controller: editableTiers[ti].value,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: isAr ? 'سعر الفرد (جنيه)' : 'EGP / person',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                    onPressed: () {
                                      setDialogState(() => editableTiers.removeAt(ti));
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            Align(
                              alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    final nextCap = (editableTiers.length + 1) * 3;
                                    editableTiers.add(MapEntry(
                                      TextEditingController(text: nextCap.toString()),
                                      TextEditingController(text: '100'),
                                    ));
                                  });
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: Text(isAr ? '+ إضافة شريحة سعر جديدة' : '+ Add Pricing Tier'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: pickUnitImage,
                            icon: const Icon(Icons.file_upload_outlined, size: 18),
                            label: Text(
                              isSalon
                                  ? (isAr ? 'رفع صورة الكرسي (ملف)' : 'Upload Chair Picture')
                                  : (isAr ? 'رفع صورة الغرفة / الملعب (ملف)' : 'Upload Room Picture'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                        ),
                        if (imageCtrl.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: isAr ? 'مسح الصورة' : 'Clear Image',
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () => setDialogState(() => imageCtrl.clear()),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: imageCtrl,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: isAr ? 'أو رابط صورة الوحدة (URL)' : 'Or Unit Picture URL',
                        hintText: 'https://images.unsplash.com/...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.link_rounded, size: 18),
                      ),
                    ),
                    if (imageCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: surfaceBg,
                            border: Border.all(color: borderColor),
                          ),
                          child: HagzySmartImage(
                            imageUrl: imageCtrl.text.trim(),
                            fit: BoxFit.cover,
                            errorWidget: Center(
                              child: Text(
                                isAr ? 'تعذر معاينة الصورة' : 'Could not preview image',
                                style: TextStyle(fontSize: 11, color: mutedColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  isAr ? 'إلغاء' : 'Cancel',
                  style: TextStyle(color: mutedColor, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kGreen),
                onPressed: () {
                  final n = nameCtrl.text.trim();
                  if (n.isEmpty) return;
                  final r = double.tryParse(rateCtrl.text.trim()) ?? item.hourlyRate;
                  final p = enablePeakPricing ? (double.tryParse(peakCtrl.text.trim()) ?? r) : r;

                  Map<String, dynamic>? resolvedTiers;
                  if (isTiered && editableTiers.isNotEmpty) {
                    resolvedTiers = {};
                    for (final t in editableTiers) {
                      final cap = t.key.text.trim();
                      final price = double.tryParse(t.value.text.trim()) ?? 0.0;
                      if (cap.isNotEmpty && price > 0) {
                        resolvedTiers[cap] = price;
                      }
                    }
                  }
                  final minCap = int.tryParse(minCapCtrl.text.trim()) ?? (isTiered ? 2 : 1);
                  final maxCap = int.tryParse(maxCapCtrl.text.trim()) ?? (isTiered ? 15 : 10);

                  setState(() {
                    _items[idx] = _EditableItem(
                      id: item.id,
                      name: n,
                      kind: kindCtrl.text.trim().isNotEmpty ? kindCtrl.text.trim() : item.kind,
                      hourlyRate: r,
                      peakRate: p,
                      description: descCtrl.text.trim(),
                      imageUrl: imageCtrl.text.trim().isNotEmpty ? imageCtrl.text.trim() : null,
                      pricingMode: isTiered ? 'per_person_tiered' : null,
                      pricingTiers: resolvedTiers,
                      minCapacity: minCap,
                      maxCapacity: maxCap,
                    );
                  });
                  Navigator.pop(ctx);
                },
                child: Text(isAr ? 'حفظ' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  // DIALOG: Add Service (Haircut, Beard, Racket)
  void _showAddServiceDialog(bool isAr) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '100');
    final minCtrl = TextEditingController(text: '30');
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final dialogBg = isDark ? const Color(0xFF111B17) : Colors.white;
    final borderColor = isDark ? const Color(0xFF1F352D) : Colors.grey.shade300;
    final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        title: Text(
          isAr ? 'إضافة خدمة أو باقة' : 'Add Service / Add-on',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textColor),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'اسم الخدمة (مثل: قص شعر وسشوار)' : 'Service Name (e.g. Haircut)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'السعر (جنيه)' : 'Price (EGP)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'المدة التقديرية (بالدقائق)' : 'Duration (Minutes)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              isAr ? 'إلغاء' : 'Cancel',
              style: TextStyle(color: mutedColor, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGreen),
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isEmpty) return;
              final p = double.tryParse(priceCtrl.text.trim()) ?? 50.0;
              final m = int.tryParse(minCtrl.text.trim()) ?? 30;

              setState(() {
                _services.add(_EditableService(
                  id: 'svc_${DateTime.now().microsecondsSinceEpoch}',
                  name: n,
                  price: p,
                  minutes: m,
                ));
              });
              Navigator.pop(ctx);
            },
            child: Text(isAr ? 'إضافة' : 'Add'),
          ),
        ],
      ),
    );
  }
}

class _EditableItem {
  final String id;
  String name;
  String kind;
  double hourlyRate;
  double peakRate;
  String description;
  String? imageUrl;
  String? pricingMode;
  Map<String, dynamic>? pricingTiers;
  int? minCapacity;
  int? maxCapacity;

  _EditableItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.hourlyRate,
    required this.peakRate,
    this.description = '',
    this.imageUrl,
    this.pricingMode,
    this.pricingTiers,
    this.minCapacity,
    this.maxCapacity,
  });
}

class _EditableService {
  final String id;
  String name;
  double price;
  int minutes;

  _EditableService({
    required this.id,
    required this.name,
    required this.price,
    required this.minutes,
  });
}
