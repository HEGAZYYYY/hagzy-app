import 'dart:convert';

/// User Profile & Hagzy Lifestyle Passport with automated reputation and balance
class UserProfile {
  final String id;
  final String phoneNumber;
  final String displayName;
  final String city;
  final double reliabilityScore; // 0.0 - 100.0 scale. Starts at 100.0
  final int completedBookingsCount;
  final int noShowCount;
  final double hagzyWalletBalance; // Instant in-app refund balance
  final List<String> badges; // ['reliable', 'shilla_leader', 'study_grind', 'gamer_vip']
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.phoneNumber,
    this.displayName = 'Hagzy Member',
    this.city = 'Kafr El Sheikh',
    this.reliabilityScore = 100.0,
    this.completedBookingsCount = 0,
    this.noShowCount = 0,
    this.hagzyWalletBalance = 0.0,
    this.badges = const ['reliable'],
    required this.createdAt,
  });

  /// Principle 5 & Fraud Prevention:
  /// If score drops below 80%, user is required to prepay 100% deposit digitally (no pay-at-venue)
  bool get requiresFullDeposit => reliabilityScore < 80.0;

  /// High-reliability perk: >95% unlocks zero-deposit weekday booking holds
  bool get hasZeroDepositPerks => reliabilityScore >= 95.0;

  /// Trust rating label in Arabic & English
  String get reliabilityTier {
    if (reliabilityScore >= 95.0) return 'Elite Member (عضو موثوق)';
    if (reliabilityScore >= 80.0) return 'Good Standing (حساب منتظم)';
    if (reliabilityScore >= 60.0) return 'Warning Tier (تحت الملاحظة)';
    return 'Restricted Tier (إيداع كامل مطلوب)';
  }

  /// Whether user can claim open challenger / open lobby spots
  bool get canJoinChallengerLobby => reliabilityScore >= 70.0;

  /// Check if user has a specific passport badge
  bool hasBadge(String badgeKey) => badges.contains(badgeKey.toLowerCase());

  /// Apply a no-show penalty (-15 points)
  UserProfile recordNoShow() {
    final newScore = (reliabilityScore - 15.0).clamp(0.0, 100.0);
    final updatedBadges = List<String>.from(badges)..remove('reliable');
    return copyWith(
      reliabilityScore: newScore,
      noShowCount: noShowCount + 1,
      badges: updatedBadges,
    );
  }

  /// Apply a completed booking reward (+2 points recovery)
  UserProfile recordCompletedBooking({bool isHost = false, String? category}) {
    final newScore = (reliabilityScore + 2.0).clamp(0.0, 100.0);
    final newCompleted = completedBookingsCount + 1;
    final updatedBadges = Set<String>.from(badges);

    if (newScore >= 95.0 && newCompleted >= 3) {
      updatedBadges.add('reliable');
    }
    if (isHost && newCompleted >= 3) {
      updatedBadges.add('shilla_leader');
    }
    if (category == 'workspace' && newCompleted >= 3) {
      updatedBadges.add('study_grind');
    }
    if (category == 'playstation' && newCompleted >= 3) {
      updatedBadges.add('gamer_vip');
    }

    return copyWith(
      reliabilityScore: newScore,
      completedBookingsCount: newCompleted,
      badges: updatedBadges.toList(),
    );
  }

  /// Add refund to wallet balance (e.g. 10-minute grace period cancellation)
  UserProfile creditWallet(double amountEgp) {
    if (amountEgp <= 0) return this;
    return copyWith(hagzyWalletBalance: hagzyWalletBalance + amountEgp);
  }

  /// Deduct balance for 1-tap checkout
  UserProfile debitWallet(double amountEgp) {
    if (amountEgp <= 0) return this;
    final newBal = (hagzyWalletBalance - amountEgp).clamp(0.0, double.infinity);
    return copyWith(hagzyWalletBalance: newBal);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone_number': phoneNumber,
        'display_name': displayName,
        'city': city,
        'reliability_score': reliabilityScore,
        'completed_bookings_count': completedBookingsCount,
        'no_show_count': noShowCount,
        'hagzy_wallet_balance': hagzyWalletBalance,
        'badges': badges,
        'created_at': createdAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    List<String> parsedBadges = [];
    if (json['badges'] is List) {
      parsedBadges = (json['badges'] as List).map((b) => b.toString()).toList();
    } else if (json['badges'] is String) {
      try {
        parsedBadges = (jsonDecode(json['badges'] as String) as List).map((b) => b.toString()).toList();
      } catch (_) {}
    }

    return UserProfile(
      id: json['id']?.toString() ?? '',
      phoneNumber: (json['phone_number'] ?? json['phone'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['name'] ?? 'Hagzy Member').toString(),
      city: json['city']?.toString() ?? 'Kafr El Sheikh',
      reliabilityScore: (json['reliability_score'] as num?)?.toDouble() ?? 100.0,
      completedBookingsCount: (json['completed_bookings_count'] as num?)?.toInt() ?? 0,
      noShowCount: (json['no_show_count'] as num?)?.toInt() ?? 0,
      hagzyWalletBalance: (json['hagzy_wallet_balance'] ?? json['walletBalance'] as num?)?.toDouble() ?? 0.0,
      badges: parsedBadges.isNotEmpty ? parsedBadges : const ['reliable'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  UserProfile copyWith({
    String? id,
    String? phoneNumber,
    String? displayName,
    String? city,
    double? reliabilityScore,
    int? completedBookingsCount,
    int? noShowCount,
    double? hagzyWalletBalance,
    List<String>? badges,
    DateTime? createdAt,
  }) =>
      UserProfile(
        id: id ?? this.id,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        displayName: displayName ?? this.displayName,
        city: city ?? this.city,
        reliabilityScore: reliabilityScore ?? this.reliabilityScore,
        completedBookingsCount: completedBookingsCount ?? this.completedBookingsCount,
        noShowCount: noShowCount ?? this.noShowCount,
        hagzyWalletBalance: hagzyWalletBalance ?? this.hagzyWalletBalance,
        badges: badges ?? this.badges,
        createdAt: createdAt ?? this.createdAt,
      );
}

