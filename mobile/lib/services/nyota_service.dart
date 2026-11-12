import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Central data access for Nyota. All money math happens in Postgres
/// (NUMERIC columns / RPC) so totals can never drift or double count.
class NyotaService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const _uuid = Uuid();

  static SupabaseClient get client => _client;
  static Session? get session => _client.auth.currentSession;
  static bool get isSignedIn => _client.auth.currentSession != null;

  // ---------------- Auth ----------------

  static Future<AuthResponse> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  static Future<AuthResponse> signUp(String email, String password, String fullName) =>
      _client.auth.signUp(email: email, password: password, data: {'full_name': fullName});

  static Future<void> signOut() => _client.auth.signOut();

  // ---------------- Events ----------------

  /// Returns the newest event, or null when the user has none yet.
  static Future<NyotaEvent?> latestEvent() async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('events')
        .select()
        .eq('owner_id', uid)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return NyotaEvent.fromMap(rows.first);
  }

  static Future<NyotaEvent> createEvent(String name, String? eventDate) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('events')
        .insert({'owner_id': uid, 'name': name, 'event_date': eventDate})
        .select()
        .single();
    return NyotaEvent.fromMap(row);
  }

  static Future<List<NyotaEvent>> listEvents() async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('events')
        .select()
        .eq('owner_id', uid)
        .order('created_at', ascending: false);
    return rows.map(NyotaEvent.fromMap).toList();
  }

  // ---------------- Dashboard ----------------

  static Future<DashboardTotals> dashboardTotals(String eventId) async {
    final map = await _client
        .rpc('get_dashboard_totals', params: {'p_event_id': eventId});
    return DashboardTotals.fromMap(Map<String, dynamic>.from(map as Map));
  }

  // ---------------- Entries ----------------

  /// Paged, optionally searched register feed. Gifts come along via join.
  static Future<List<GuestEntry>> fetchEntries(
    String eventId, {
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
      var q = _client
        .from('guest_entries')
        .select('*, gifts(*)')
        .eq('event_id', eventId);
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      q = q.or('guest_name.ilike.%$s%,father_name.ilike.%$s%,village.ilike.%$s%');
    }
    final rows = await q
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(GuestEntry.fromMap).toList();
  }

  /// Food Only quick save. Amount compulsory; name optional.
  /// Uses a client-generated id so a retry can never create a duplicate.
  static Future<String> saveFoodOnly({
    required String eventId,
    required double amount,
    String? guestName,
  }) async {
    final uid = _client.auth.currentUser!.id;
    final clientId = _uuid.v4();
    final row = await _client
        .from('guest_entries')
        .upsert(
      {
        'client_id': clientId,
        'event_id': eventId,
        'owner_id': uid,
        'category': 'food_only',
        'guest_name': (guestName == null || guestName.trim().isEmpty) ? null : guestName.trim(),
        'cash_amount': amount,
      },
      onConflict: 'client_id',
      ignoreDuplicates: true,
    )
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Nyota with Gifts: creates the entry, then its gifts (images uploaded by
  /// the caller who stores each image path inside [gifts] beforehand).
  static Future<String> saveNyotaEntry({
    required String eventId,
    required double cashAmount,
    String? guestName,
    String? fatherName,
    String? village,
    List<Gift> gifts = const [],
  }) async {
    final uid = _client.auth.currentUser!.id;
    final clientId = _uuid.v4();
    final row = await _client
        .from('guest_entries')
        .upsert(
      {
        'client_id': clientId,
        'event_id': eventId,
        'owner_id': uid,
        'category': 'nyota_gifts',
        'guest_name': (guestName?.trim().isEmpty ?? true) ? null : guestName!.trim(),
        'father_name': (fatherName?.trim().isEmpty ?? true) ? null : fatherName!.trim(),
        'village': (village?.trim().isEmpty ?? true) ? null : village!.trim(),
        'cash_amount': cashAmount,
      },
      onConflict: 'client_id',
      ignoreDuplicates: true,
    )
        .select('id')
        .single();
    final entryId = row['id'] as String;
    if (gifts.isNotEmpty) {
      await _client.from('gifts').insert(
            gifts.map((g) => {...g.toInsert(), 'entry_id': entryId, 'owner_id': uid}).toList(),
          );
    }
    return entryId;
  }

  static Future<void> updateEntry(
    GuestEntry entry, {
    required double cashAmount,
    String? guestName,
    String? fatherName,
    String? village,
    List<Gift> gifts = const [],
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('guest_entries').update({
      'guest_name': (guestName?.trim().isEmpty ?? true) ? null : guestName!.trim(),
      'father_name': (fatherName?.trim().isEmpty ?? true) ? null : fatherName!.trim(),
      'village': (village?.trim().isEmpty ?? true) ? null : village!.trim(),
      'cash_amount': cashAmount,
    }).eq('id', entry.id);

    // Replace the gift list wholesale (images already uploaded for new gifts).
    await _client.from('gifts').delete().eq('entry_id', entry.id);
    if (gifts.isNotEmpty) {
      await _client.from('gifts').insert(
            gifts.map((g) => {...g.toInsert(), 'entry_id': entry.id, 'owner_id': uid}).toList(),
          );
    }
  }

  static Future<void> deleteEntry(String entryId) =>
      _client.from('guest_entries').delete().eq('id', entryId);

  /// Adds gifts to an existing entry (images already uploaded).
  static Future<void> addGiftsToEntry({
    required String eventId,
    required String entryId,
    required List<GiftPayload> gifts,
  }) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('gifts').insert(
          gifts
              .map((g) => {
                    'entry_id': entryId,
                    'owner_id': uid,
                    'name': g.name,
                    'description': g.description,
                    'image_path': g.imagePath,
                  })
              .toList(),
        );
  }

  // ---------------- Storage ----------------

  /// Uploads already-compressed bytes to the signed-in user's folder,
  /// reporting actual bytes-sent progress. Falls back internally to
  /// client-side retries; never uploads the original file twice silently.
  static Future<String> uploadGiftImage(
    String entryId,
    Uint8List bytes, {
    void Function(double sentRatio)? onProgress,
  }) async {
    final uid = _client.auth.currentUser!.id;
    final path = '$uid/$entryId/${_uuid.v4()}.jpg';

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _rawUpload(path, bytes, onProgress);
        return path;
      } catch (e) {
        lastError = e;
        if (onProgress != null) onProgress(0);
      }
    }
    throw Exception('Image upload failed after 3 attempts: $lastError');
  }

  /// Direct POST to the storage API so we can observe upload progress.
  /// Mirrors what `uploadBinary` does, byte-chunk by byte-chunk.
  static Future<void> _rawUpload(
    String path,
    Uint8List bytes,
    void Function(double)? onProgress,
  ) async {
    final api = _client.storage.from('gift-images');
    final token = _client.auth.currentSession!.accessToken;
    final uri = Uri.parse('${api.url}/object/$path');
    final total = bytes.length;
    var sent = 0;

    final request = http.StreamedRequest('POST', uri)
      ..headers.addAll({
        'authorization': 'Bearer $token',
        'apikey': token,
        'content-type': 'image/jpeg',
        'cache-control': '3600',
        'x-upsert': 'false',
        'content-length': '$total',
      });

    // Splitting into 64 kB chunks so progress updates as bytes hit the wire.
    const chunkSize = 64 * 1024;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize) < bytes.length ? (i + chunkSize) : bytes.length;
      request.sink.add(bytes.sublist(i, end));
      sent = end;
      if (onProgress != null) onProgress(sent / total);
    }
    await request.sink.close();
    if (onProgress != null) onProgress(1);

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed (${response.statusCode}): $body');
    }
  }

  static String publicUrl(String path) =>
      _client.storage.from('gift-images').getPublicUrl(path);

  static Future<void> deleteGiftImage(String path) async {
    try {
      await _client.storage.from('gift-images').remove([path]);
    } catch (_) {
      // Deleting storage objects is best-effort; the DB record is the truth.
    }
  }
}
