import 'package:flutter_test/flutter_test.dart';

import 'package:nyota/models.dart';

void main() {
  test('DashboardTotals parses NUMERIC values coming back as strings', () {
    final t = DashboardTotals.fromMap({
      'total_guests': 42,
      'total_nyota_cash': '12345.50',
      'total_food_only': '6789',
      'total_cash': '19134.50',
      'total_gifts': 7,
    });
    expect(t.totalGuests, 42);
    expect(t.totalNyotaCash, 12345.50);
    expect(t.totalFoodOnly, 6789);
    expect(t.totalCash, 19134.50);
    expect(t.totalGifts, 7);
  });

  test('GuestEntry parses gifts and category', () {
    final e = GuestEntry.fromMap({
      'id': 'e1',
      'event_id': 'ev1',
      'category': 'nyota_gifts',
      'guest_name': 'Ramesh',
      'father_name': 'Suresh',
      'village': 'Kotra',
      'cash_amount': '501',
      'gifts': [
        {
          'id': 'g1',
          'name': 'Brass Diya',
          'description': null,
          'image_path': null,
        },
        {
          'id': 'g2',
          'name': 'Saree',
          'description': 'Banarasi silk',
          'image_path': 'uid/e1/x.jpg',
        },
      ],
    });
    expect(e.category, EntryCategory.nyotaGifts);
    expect(e.cashAmount, 501);
    expect(e.gifts.length, 2);
    expect(e.gifts[1].imagePath, 'uid/e1/x.jpg');
  });

  test('Food-only entry without name falls back to Guest', () {
    final e = GuestEntry.fromMap({
      'id': 'e2',
      'event_id': 'ev1',
      'category': 'food_only',
      'cash_amount': 51,
      'gifts': [],
    });
    expect(e.displayName, 'Guest');
    expect(e.category, EntryCategory.foodOnly);
  });
}
