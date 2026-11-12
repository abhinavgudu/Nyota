/// Data models for Nyota.
library;

class NyotaEvent {
  final String id;
  final String name;
  final String? eventDate;
  final String? joinCode;

  NyotaEvent({required this.id, required this.name, this.eventDate, this.joinCode});

  factory NyotaEvent.fromMap(Map<String, dynamic> map) => NyotaEvent(
        id: map['id'] as String,
        name: (map['name'] ?? '') as String,
        eventDate: map['event_date'] as String?,
        joinCode: map['join_code'] as String?,
      );
}

class Gift {
  final String id;
  final String name;
  final String? description;
  final String? imagePath;

  Gift({required this.id, required this.name, this.description, this.imagePath});

  factory Gift.fromMap(Map<String, dynamic> map) => Gift(
        id: map['id'] as String,
        name: (map['name'] ?? '') as String,
        description: map['description'] as String?,
        imagePath: map['image_path'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'description': description,
        'image_path': imagePath,
      };
}

/// Payload for a gift row once its image (if any) has been uploaded.
class GiftPayload {
  GiftPayload({required this.name, this.description, this.imagePath});

  final String name;
  final String? description;
  final String? imagePath;
}

enum EntryCategory { nyotaGifts, foodOnly }

extension EntryCategoryX on EntryCategory {
  String get value => this == EntryCategory.nyotaGifts ? 'nyota_gifts' : 'food_only';

  String get label => this == EntryCategory.nyotaGifts ? 'Nyota with Gifts' : 'Food Only';

  static EntryCategory fromValue(String v) =>
      v == 'food_only' ? EntryCategory.foodOnly : EntryCategory.nyotaGifts;
}

class GuestEntry {
  final String id;
  final String eventId;
  final EntryCategory category;
  final String? guestName;
  final String? fatherName;
  final String? village;
  final double cashAmount;
  final List<Gift> gifts;
  final String? createdAt;

  GuestEntry({
    required this.id,
    required this.eventId,
    required this.category,
    this.guestName,
    this.fatherName,
    this.village,
    required this.cashAmount,
    this.gifts = const [],
    this.createdAt,
  });

  String get displayName {
    final n = guestName;
    if (n != null && n.trim().isNotEmpty) return n;
    return 'Guest';
  }

  factory GuestEntry.fromMap(Map<String, dynamic> map) => GuestEntry(
        id: map['id'] as String,
        eventId: map['event_id'] as String,
        category: EntryCategoryX.fromValue((map['category'] ?? '') as String),
        guestName: map['guest_name'] as String?,
        fatherName: map['father_name'] as String?,
        village: map['village'] as String?,
        cashAmount: _toNum(map['cash_amount']),
        gifts: ((map['gifts'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Gift.fromMap)
            .toList(),
        createdAt: map['created_at'] as String?,
      );

  static double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

class DashboardTotals {
  final int totalGuests;
  final double totalNyotaCash;
  final double totalFoodOnly;
  final double totalCash;
  final int totalGifts;

  DashboardTotals({
    required this.totalGuests,
    required this.totalNyotaCash,
    required this.totalFoodOnly,
    required this.totalCash,
    required this.totalGifts,
  });

  factory DashboardTotals.fromMap(Map<String, dynamic> map) => DashboardTotals(
        totalGuests: (map['total_guests'] as num?)?.toInt() ?? 0,
        totalNyotaCash: _toNum(map['total_nyota_cash']),
        totalFoodOnly: _toNum(map['total_food_only']),
        totalCash: _toNum(map['total_cash']),
        totalGifts: (map['total_gifts'] as num?)?.toInt() ?? 0,
      );

  static double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
