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
        peakRate: i.multiRate > 0 ? i.multiRate : i.hourlyRate * 1.25,
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
        _EditableItem(id: 'chair_1', name: 'Master Barber Chair 1', kind: 'Master Station', hourlyRate: 150, peakRate: 200),
        _EditableItem(id: 'chair_2', name: 'Styling Chair 2', kind: 'Standard', hourlyRate: 120, peakRate: 150),
        _EditableItem(id: 'chair_vip', name: 'VIP Private Grooming Suite', kind: 'VIP Suite', hourlyRate: 250, peakRate: 300),
      ]);
      _services.addAll([
        _EditableService(id: 'svc_hair', name: 'Haircut & Styling', price: 100, minutes: 30),
        _EditableService(id: 'svc_beard', name: 'Hot Towel Beard Grooming', price: 70, minutes: 20),
        _EditableService(id: 'svc_vip', name: 'VIP Total Grooming Package', price: 250, minutes: 60),
      ]);
    } else if (type == VenueType.lounge) {
      _items.addAll([
        _EditableItem(id: 'ps_room_1', name: 'PS5 Room 1 (65" 4K OLED)', kind: 'VIP Lounge', hourlyRate: 80, peakRate: 100),
        _EditableItem(id: 'ps_room_2', name: 'PS5 Room 2 (Standard)', kind: 'Standard Room', hourlyRate: 60, peakRate: 80),
        _EditableItem(id: 'billiard_1', name: 'Tournament Billiards Table', kind: 'Billiards', hourlyRate: 70, peakRate: 90),
      ]);
    } else {
      _items.addAll([
        _EditableItem(id: 'court_1', name: 'Court 1 (Panoramic Glass)', kind: 'Panoramic', hourlyRate: 400, peakRate: 500),
        _EditableItem(id: 'court_2', name: 'Court 2 (Standard)', kind: 'Standard', hourlyRate: 350, peakRate: 450),
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
      multiRate: i.peakRate,
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.black87),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              isEditing
                  ? (isAr ? 'تعديل وتحديث المكان' : 'Renovate / Edit Venue')
                  : (isAr ? 'إضافة مكان جديد' : 'Add a venue'),
              style: const TextStyle(
                color: Colors.black87,
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
                      label: Text(city, style: const TextStyle(fontSize: 11.5)),
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
                      label: Text('$percent%'),
                      onPressed: () {
                        setState(() {
                          _depositPercentController.text = percent.toString();
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                const Divider(),
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Center(
                      child: Text(
                        _selectedType == VenueType.salon
                            ? (isAr ? 'لم تتم إضافة أي كراسي' : 'No chairs added yet')
                            : (isAr ? 'لم تتم إضافة أي غرف' : 'No rooms added yet'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: kSurfaceTint,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _selectedType == VenueType.salon ? Icons.chair_rounded : Icons.sports_tennis_rounded,
                              color: kGreen,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.kind,
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(
                                      '${item.hourlyRate.toStringAsFixed(0)} EGP/hr',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: kGreen,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (item.peakRate > 0 && item.peakRate != item.hourlyRate)
                                      Text(
                                        '• Peak: ${item.peakRate.toStringAsFixed(0)} EGP',
                                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
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
                const Divider(),
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
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
                  )
                else
                  ..._services.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final svc = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: kGreen),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${svc.name} (${svc.minutes} min)',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                            onPressed: () => setState(() => _services.removeAt(idx)),
                          ),
                        ],
                      ),
                    );
                  }),

                // SECTION 4: Photos & Amenities
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                _buildSectionHeader(
                  icon: Icons.add_photo_alternate_rounded,
                  title: isAr ? 'صور المكان والمميزات' : 'Pictures & Amenities',
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
                      label: Text(preset['label']!, style: const TextStyle(fontSize: 11.5)),
                      selected: _imageUrlController.text.trim() == preset['url'],
                      selectedColor: kSurfaceTint,
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
                        color: Colors.grey.shade100,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: HagzySmartImage(
                        imageUrl: _imageUrlController.text.trim(),
                        fit: BoxFit.cover,
                        errorWidget: Center(
                          child: Text(
                            isAr ? 'تعذر معاينة الصورة' : 'Could not preview image',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  isAr ? 'تجهيزات ومميزات المكان:' : 'Available Amenities:',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allAmenities.map((amenity) {
                    final selected = _selectedAmenities.contains(amenity);
                    return FilterChip(
                      label: Text(amenity, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      selectedColor: kSurfaceTint,
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
                const Divider(),
                const SizedBox(height: 12),
                _buildSectionHeader(
                  icon: Icons.account_balance_wallet_rounded,
                  title: isAr ? 'طرق الدفع ومواعيد العمل' : 'Payout Accounts & Hours',
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
                          return DropdownMenuItem(value: h, child: Text(display, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) => setState(() => _openHour = val ?? 10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _closeHour,
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
                          return DropdownMenuItem(value: h, child: Text(display, overflow: TextOverflow.ellipsis));
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
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    isAr ? 'إلغاء' : 'Cancel',
                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
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

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: kGreen),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ],
    );
  }

  // DIALOG: Add Item (Room / Chair)
  void _showAddItemDialog(bool isAr) {
    final isSalon = _selectedType == VenueType.salon;
    final nameCtrl = TextEditingController(
      text: isSalon ? 'Chair ${_items.length + 1}' : 'Room ${_items.length + 1}',
    );
    final kindCtrl = TextEditingController(text: isSalon ? 'Standard Station' : 'Standard');
    final rateCtrl = TextEditingController(text: isSalon ? '150' : '350');
    final peakCtrl = TextEditingController(text: isSalon ? '200' : '450');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isSalon
              ? (isAr ? 'إضافة كرسي حلاقة جديد' : 'Add New Salon Chair')
              : (isAr ? 'إضافة غرفة أو ملعب جديد' : 'Add New Room or Court'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              TextFormField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'السعر العادي للساعة (جنيه)' : 'Regular Hourly Rate (EGP)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: peakCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'سعر وقت الذروة / المساء (جنيه)' : 'Peak / Evening Rate (EGP)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  helperText: isAr ? 'تغير السعر حسب وقت الحجز' : 'Time-based dynamic rate',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGreen),
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isEmpty) return;
              final r = double.tryParse(rateCtrl.text.trim()) ?? 150.0;
              final p = double.tryParse(peakCtrl.text.trim()) ?? r;

              setState(() {
                _items.add(_EditableItem(
                  id: 'unit_${DateTime.now().microsecondsSinceEpoch}',
                  name: n,
                  kind: kindCtrl.text.trim().isNotEmpty ? kindCtrl.text.trim() : 'Standard',
                  hourlyRate: r,
                  peakRate: p,
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

  // DIALOG: Edit Item
  void _showEditItemDialog(_EditableItem item, int idx, bool isAr) {
    final nameCtrl = TextEditingController(text: item.name);
    final kindCtrl = TextEditingController(text: item.kind);
    final rateCtrl = TextEditingController(text: item.hourlyRate.toStringAsFixed(0));
    final peakCtrl = TextEditingController(text: item.peakRate.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAr ? 'تعديل تفاصيل الوحدة والأسعار' : 'Edit Room / Chair & Rates',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              TextFormField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'السعر العادي للساعة (جنيه)' : 'Regular Hourly Rate (EGP)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: peakCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'سعر وقت الذروة / المساء (جنيه)' : 'Peak / Evening Rate (EGP)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGreen),
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isEmpty) return;
              final r = double.tryParse(rateCtrl.text.trim()) ?? item.hourlyRate;
              final p = double.tryParse(peakCtrl.text.trim()) ?? r;

              setState(() {
                _items[idx] = _EditableItem(
                  id: item.id,
                  name: n,
                  kind: kindCtrl.text.trim().isNotEmpty ? kindCtrl.text.trim() : item.kind,
                  hourlyRate: r,
                  peakRate: p,
                );
              });
              Navigator.pop(ctx);
            },
            child: Text(isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
  }

  // DIALOG: Add Service (Haircut, Beard, Racket)
  void _showAddServiceDialog(bool isAr) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '100');
    final minCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAr ? 'إضافة خدمة أو باقة' : 'Add Service / Add-on',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
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

  _EditableItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.hourlyRate,
    required this.peakRate,
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
