/// ============================================================================
///  Arabic-aware normalisation — literal Dart port
/// ============================================================================
///
///  Ported 1:1 from the Vue project:
///    • `arNormSql` / `arNormJs`      ← src/platform/db/schema.js
///    • `arNormPhoneSql`              ← src/platform/db/schema.js
///    • `normPhone`                   ← src/utils/search.js (single source of
///                                      truth for phone canonicalisation)
///
///  The SQL builders MUST stay byte-compatible with the JS originals so a
///  Flutter-written row and a Vue-written row normalise identically — this is
///  what allows both apps to run side-by-side on the same database during the
///  parallel-run rollout.
library;

/// Tashkeel / harakat range stripped by normalisation: U+064B..U+065F + U+0670.
final List<String> _arStrip = [
  for (int c = 0x064B; c <= 0x065F; c++) String.fromCharCode(c),
  'ٰ',
];

/// Character folds: hamza forms → bare alef/yaa/waw, taa marbuta → haa,
/// alef maqsura → yaa. Order matters (mirrors the JS array order).
const List<(String, String)> _arFold = [
  ('أ', 'ا'), // أ → ا
  ('إ', 'ا'), // إ → ا
  ('آ', 'ا'), // آ → ا
  ('ٱ', 'ا'), // ٱ → ا
  ('ة', 'ه'), // ة → ه
  ('ى', 'ي'), // ى → ي
  ('ئ', 'ي'), // ئ → ي
  ('ؤ', 'و'), // ؤ → و
];

/// SQL expression that normalises column/expr [col] like Dart [arNorm].
/// Literal port of `arNormSql()` — produces the exact same nested REPLACE
/// chain so FTS triggers built by either codebase are identical.
String arNormSql(String col) {
  var expr = col;
  for (final ch in _arStrip) {
    expr = "REPLACE($expr,'$ch','')";
  }
  for (final (a, b) in _arFold) {
    expr = "REPLACE($expr,'$a','$b')";
  }
  return 'LOWER(TRIM($expr))';
}

/// Dart twin of [arNormSql] — literal port of `arNormJs()` in schema.js.
String arNorm(String? s) {
  if (s == null || s.isEmpty) return '';
  const fold = {
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ة': 'ه',
    'ى': 'ي',
    'ئ': 'ي',
    'ؤ': 'و',
  };
  final out = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    out.write(fold[ch] ?? ch);
  }
  return out
      .toString()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .trim()
      .toLowerCase();
}

/// Search-layer normaliser — literal port of `normAr()` in utils/search.js.
/// Same folds + strip as [arNorm] but WITHOUT the trim (the two JS originals
/// genuinely differ on that point; both are preserved faithfully).
String normAr(String? s) {
  if (s == null || s.isEmpty) return '';
  const fold = {
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ة': 'ه',
    'ى': 'ي',
    'ئ': 'ي',
    'ؤ': 'و',
  };
  final out = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    out.write(fold[ch] ?? ch);
  }
  return out
      .toString()
      .replaceAll(RegExp(r'[ً-ٰٟ]'), '')
      .toLowerCase();
}

/// SQL twin of [normPhone] — literal port of `arNormPhoneSql()` in schema.js.
/// Same steps, same order:
///   1. fold Arabic-Indic (٠-٩) digits to ASCII
///   2. strip the common phone separators (space, dash, parens, +, ., /, NBSP)
///   3. drop a leading `00`            (CASE/substr)
///   4. drop the Libya code `218`      (CASE/substr)
///   5. drop leading trunk zero(s)     (ltrim)
String arNormPhoneSql(String col) {
  var e = col;
  // 1. Arabic-Indic digit folding (٠..٩ → 0..9)
  const ai = [
    '٠', '١', '٢', '٣', '٤',
    '٥', '٦', '٧', '٨', '٩',
  ];
  for (var i = 0; i < ai.length; i++) {
    e = "REPLACE($e,'${ai[i]}','$i')";
  }
  // 2. strip common separators
  for (final sep in [' ', '-', '(', ')', '+', '.', '/', ' ', '\t']) {
    e = "REPLACE($e,'$sep','')";
  }
  // 3. drop leading '00'
  e = "CASE WHEN substr($e,1,2)='00' THEN substr($e,3) ELSE $e END";
  // 4. drop Libya country code '218'
  e = "CASE WHEN substr($e,1,3)='218' THEN substr($e,4) ELSE $e END";
  // 5. drop leading trunk zero(s)
  return "ltrim($e,'0')";
}

/// Canonical phone form — literal port of `normPhone()` in utils/search.js.
/// SINGLE SOURCE OF TRUTH for phone normalisation (phone-anchored identity).
String normPhone(Object? s) {
  if (s == null || (s is String && s.isEmpty)) return '';
  final str = s.toString();
  // 1. fold Arabic-Indic / Persian digits to ASCII
  final t = StringBuffer();
  for (final rune in str.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      t.write(rune - 0x0660); // ٠-٩
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      t.write(rune - 0x06F0); // ۰-۹
    } else {
      t.write(String.fromCharCode(rune));
    }
  }
  // 2. keep digits only
  var d = t.toString().replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  // 3. drop international 00 prefix
  if (d.startsWith('00')) d = d.substring(2);
  // 4. drop Libya country code
  if (d.startsWith('218')) d = d.substring(3);
  // 5. drop leading trunk zero(s)
  d = d.replaceFirst(RegExp(r'^0+'), '');
  return d;
}
