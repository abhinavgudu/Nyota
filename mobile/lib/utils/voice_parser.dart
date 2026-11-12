/// Parses spoken text into values suitable for Nyota's fast-entry fields.
class VoiceParse {
  /// Extracts a money/number amount from speech.
  /// Handles: "502", "₹501", "five hundred and two", "one thousand one", etc.
  /// Returns null if nothing usable found.
  static String? amount(String raw) {
    final t = raw.toLowerCase().trim();
    if (t.isEmpty) return null;

    // If the speech already contains digits, prefer extracting the full number.
    final digitMatch = RegExp(r'[\d,]+(?:\.\d+)?').allMatches(t.replaceAll(' ', ''));
    if (digitMatch.isNotEmpty) {
      // pick the longest digit sequence (handles "rupees 1,001")
      final best = digitMatch.map((m) => m.group(0)!.replaceAll(',', '')).reduce(
            (a, b) => a.length >= b.length ? a : b,
          );
      final n = double.tryParse(best);
      if (n != null && n >= 0) {
        return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
      }
    }

    // Word-based parsing (English, common in en-IN recognition).
    final n = _wordsToNumber(t);
    if (n != null && n > 0) return n.toStringAsFixed(0);
    return null;
  }

  /// Cleans up recognized text for a name/village field.
  static String text(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    // Capitalize words nicely.
    s = s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return s;
  }

  static int? _wordsToNumber(String t) {
    // Normalize
    var s = t
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) return null;

    const small = <String, int>{
      'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
      'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
      'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40,
      'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
      // common Hindi number words sometimes returned in Latin script
      'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'paanch': 5, 'panch': 5,
      'chhah': 6, 'che': 6, 'saat': 7, 'aath': 8, 'ath': 8, 'nau': 9,
      'das': 10, 'gyarah': 11, 'barah': 12, 'terah': 13, 'chaudah': 14,
      'pandrah': 15, 'solah': 16, 'satrah': 17, 'atharah': 18, 'unnis': 19,
      'bees': 20, 'pachees': 25, 'pachchis': 25, 'tees': 30, 'chalis': 40,
      'pachas': 50, 'saath': 60, 'sath': 60, 'sattar': 70, 'assi': 80,
      'nabbe': 90, 'sau': 100, 'so': 100,
    };
    const multipliers = <String, int>{
      'hundred': 100, 'sau': 100, 'so': 100,
      'thousand': 1000, 'hazaar': 1000, 'hazar': 1000,
      'lakh': 100000, 'lac': 100000,
    };

    final tokens = s.split(' ').where((w) => w.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    // If nothing looks like a number word, bail.
    final hasNumWord = tokens.any((w) => small.containsKey(w) || multipliers.containsKey(w));
    if (!hasNumWord) return null;

    int total = 0;
    int current = 0;
    bool any = false;
    for (final w in tokens) {
      if (w == 'and' || w == 'rupees' || w == 'rupee' || w == 'rs' || w == 'rupaye') {
        continue;
      }
      if (small.containsKey(w)) {
        final v = small[w]!;
        // "sau" is in small as 100 for lone use, but treat as multiplier contextually
        if ((w == 'sau' || w == 'so') && current > 0 && current < 100) {
          current = current * 100;
        } else {
          current += v;
        }
        any = true;
        continue;
      }
      if (multipliers.containsKey(w)) {
        final m = multipliers[w]!;
        if (current == 0) current = 1;
        if (m == 100) {
          current = current * 100;
        } else {
          total += current * m;
          current = 0;
        }
        any = true;
        continue;
      }
      // ignore unknown tokens (e.g. "only")
    }
    if (!any) return null;
    final result = total + current;
    if (result <= 0 || result > 100000000) return null;
    return result;
  }
}
