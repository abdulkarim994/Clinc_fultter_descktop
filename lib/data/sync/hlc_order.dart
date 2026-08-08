/// ============================================================================
///  HLC-aware read-order comparator — literal port of sync/hlcOrder.js
/// ============================================================================
///
///  A SINGLE comparator both read paths use to pick the newer of two copies:
///    - both rows carry `_hlc` → HLC total order (clock-skew proof),
///    - otherwise → legacy `_mod` / `updated_at` wall-millis comparison, with
///      a stable "HLC row wins" tiebreak on equal millis.
library;

import 'hlc.dart';

typedef SyncRow = Map<String, Object?>;

/// Legacy wall-millis for a row: numeric `_mod`, else parsed
/// `updated_at`/`updatedAt`, else 0 (mirrors the old `_modOf` exactly).
int legacyMillis(SyncRow? item) {
  final mod = item?['_mod'];
  if (mod is num) return mod.toInt();
  final ts = item?['updated_at'] ?? item?['updatedAt'];
  if (ts is String && ts.isNotEmpty) {
    final parsed = DateTime.tryParse(ts);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  return 0;
}

/// Normalise a row into its comparable stamp: HLC string (if any) + millis.
({String? hlc, int ms}) rowStamp(SyncRow? item) {
  final raw = item?['_hlc'];
  final hlcStr = (raw != null && '$raw'.isNotEmpty) ? '$raw' : null;
  return (hlc: hlcStr, ms: hlcStr != null ? hlcMillis(hlcStr) : legacyMillis(item));
}

/// Total-order comparison for last-writer-wins.
/// Returns >0 when [a] is newer, <0 when [b] is newer, 0 on a tie.
int compareRows(SyncRow? a, SyncRow? b) {
  final sa = rowStamp(a);
  final sb = rowStamp(b);
  if (sa.hlc != null && sb.hlc != null) {
    if (sa.hlc == sb.hlc) return 0;
    return isNewer(sa.hlc, sb.hlc) ? 1 : -1;
  }
  if (sa.ms != sb.ms) return sa.ms > sb.ms ? 1 : -1;
  if ((sa.hlc != null) != (sb.hlc != null)) return sa.hlc != null ? 1 : -1;
  return 0;
}

/// Should the incoming row [x] replace the previously-kept row [prev]?
/// True when newer-or-equal (preserves the historical `>=` semantics so a
/// later-seen equal row wins and source order stays stable).
bool shouldReplace(SyncRow? x, SyncRow? prev) {
  if (prev == null) return true;
  return compareRows(x, prev) >= 0;
}
