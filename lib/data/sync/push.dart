/// ============================================================================
///  PUSH — literal port of sync/push.js (dirty rows → apply_changes)
/// ============================================================================
///
///  Contract preserved verbatim:
///   - dirty rows (tombstones included), oldest `_mod` first (causal order)
///   - idempotent ops: op_id = `<entity>:<id>:<hlc>` (server dedupe ledger)
///   - on ack, clear `_dirty` ONLY if the local `_hlc` still matches
///   - failed rows stay dirty; attempts tracked; quarantine after MAX_ATTEMPTS
///     (never auto-deleted; surfaced as "needs attention")
library;

import 'dart:convert';

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'context.dart';
import 'db_sync.dart';
import 'entities.dart';
import 'merge/descriptors.dart' show splitSyncColumns;
import 'merge/shadow_store.dart' show setShadow;
import 'transport.dart';

const batchLimit = 200;
const maxAttempts = 8;
const attemptsKey = 'sync.attempts';
const quarantineKey = 'sync.quarantine';

String _keyOf(String entity, Object? id) => '$entity:$id';

Object? _safeParse(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return s;
  }
}

/// م76 — حارس الأنواع عند حدود الشبكة: لا قيمة منطقية تغادر الجهاز.
///
/// العلة التي استدعته: مسار التركيبات كان يكتب `isDebt` منطقيةً خاماً،
/// والحقل ليس عموداً مرقّى في `prosthetics`، فكان يُخزَّن في كتلة `data`
/// منطقياً ثم يُدفع كما هو. على Postgres يُرجع `payload->>'isDebt'` النصّ
/// `'true'` فيرفضه `::int`، **وصفٌّ واحد فاسد يُسقط التقرير الشهري كلّه لا
/// سطراً منه**. (محلياً لا أثر: `json_extract` في SQLite يُطبّع المنطقي
/// إلى 0/1 — لذلك ظلّت العلة غير مرئية من داخل التطبيق.)
///
/// إصلاح موضع الكتابة يعالج المسار المعروف؛ هذا الحارس يُغلق **الفئة**:
/// أي مسار كتابة قائم أو قادم يعجز عن تسريب نوع منطقي إلى الشبكة. وهو
/// المكان الصحيح للحارس لأنه المَخرج الوحيد من الجهاز.
///
/// **النطاق مقصود — المستوى الأعلى من صفوف الكيانات وحده:**
///   • حمولة `settings` مستثناة تماماً: حقل `value` يحمل إعدادات الحساب
///     المحلَّلة وفيها مفاتيح منطقية **مشروعة** (أوضاع عرض وأعلام واجهة)،
///     وتطبيعها يفسد دلالتها ويكسر الدمج البنيوي للإعدادات.
///   • القيم المتداخلة (`report` و`installments` و`_rateSnapshot`) لا تُمسّ:
///     فئة العلة هي الأعلام المسطّحة، والتوغّل في البنى المتداخلة يغيّر
///     دلالةً لم تُطلَب ويخاطر بما لا يعالجه.
///   • `_deleted` غير معنيّ أصلاً: الخادم يشتقّه من نوع العملية لا من
///     الحمولة (عمود على `sync_rows`)، وهو أساساً عدد قادم من SQLite.
Map<String, Object?> normalizeWireFlags(Map<String, Object?> payload) {
  for (final k in payload.keys.toList()) {
    final v = payload[k];
    if (v is bool) payload[k] = v ? 1 : 0;
  }
  return payload;
}

/// Build the wire payload for one dirty row.
WireOp buildOp(SyncContext ctx, String entity, Row row) {
  final id = row['id'];
  final action = jsNumber(row['_deleted']) == 1 ? 'delete' : 'upsert';
  Map<String, Object?> payload;
  if (entity == 'settings') {
    final v = row['value'];
    payload = {
      'id': id,
      'value': v is String ? _safeParse(v) : v,
      'clinic_id': jsOr(row['clinic_id'], ''),
      '_hlc': row['_hlc'],
      '_origin': jsOr(row['_origin'], ctx.deviceId),
    };
  } else {
    payload = Map<String, Object?>.from(row);
    payload.remove('data'); // fields already merged onto the row
    payload.remove('_dirty'); // local-only outbox flag; never travels
    payload.remove('server_seq'); // server owns this; assigned on apply
    // م65 — المصغّرة محلية بحتة متى كان R2 مفعّلاً: الأجهزة الأخرى ترطّبها
    // من العامل عبر `?v=thumb` (مسار _restore القائم). بلا R2 تبقى تسافر
    // لأنها حينها السبيل الوحيد للمعاينة على الجهاز الآخر.
    if (entity == 'xrays' && ctx.hasCloudImages()) {
      payload.remove('thumbnail_data');
    }
    payload['id'] = id;
    payload['_origin'] = jsOr(row['_origin'], ctx.deviceId);
    // م76 — آخر ما يمرّ قبل السلك: لا منطقي يغادر (انظر normalizeWireFlags).
    normalizeWireFlags(payload);
  }
  return WireOp(
    opId: '$entity:$id:${row['_hlc']}',
    entity: entity,
    action: action,
    row: payload,
    pushedHlc: '${row['_hlc']}',
  );
}

/// Ensure a dirty row carries an HLC; stamp + persist one if missing so the
/// pushed op_id is stable and the clocks agree.
String ensureHlc(SyncContext ctx, String entity, Row row) {
  final existing = row['_hlc'];
  if (existing != null && existing != '') return '$existing';
  final hlc = ctx.tick();
  row['_hlc'] = hlc;
  final repo = repoFor(ctx, entity);
  if (repo != null) {
    try {
      repo.upsert({...row, '_hlc': hlc});
    } catch (_) {/* best-effort */}
  }
  return hlc;
}

/// Clear `_dirty` (conditionally) and store `server_seq` after an ack.
void markRowSynced(SyncContext ctx, String entity, String id, int? serverSeq,
    String pushedHlc) {
  if (entity == 'settings') {
    final local = getRowRaw(ctx.db, 'settings', id);
    if (local == null) return;
    if ('${local['_hlc']}' != pushedHlc) return; // re-edited; keep dirty
    ctx.db.execute('UPDATE settings SET _dirty = 0 WHERE id = ?', [id]);
    return;
  }
  final repo = repoFor(ctx, entity);
  if (repo == null) return;
  final local = getRowRaw(ctx.db, entity, id);
  if (local == null) return;
  final stillSame = '${local['_hlc']}' == pushedHlc;
  final updated = <String, Object?>{...local, '_dirty': stillSame ? 0 : 1};
  if (serverSeq != null) updated['server_seq'] = serverSeq;
  try {
    repo.upsert(updated);
    // م84 — تثبيت لقطة الأساس عند تأكيد الدفع: هذا هو **المكان الصحيح** له.
    //
    //  القيمة التي دفعناها وأقرّها الخادم صارت الآن الأساس المشترك الحقيقي
    //  للدمج الثلاثي — الخادم يحملها، وكل جهاز سيراها. وبلا تثبيتها هنا
    //  تبقى اللقطة عالقةً عند ما قبل تعديلنا (v27 يتخطّى تقدّمها على صدى
    //  الدفع عمداً، خوفاً من عطلٍ آخر)، فيُقرأ **تراجعُ جهازٍ آخر** إلى تلك
    //  القيمة القديمة «تغييراً محلياً فقط ⇒ يفوز المحلي»، فيُهمَل التراجع
    //  ويُعاد دفع قيمتنا فوقه: تباعدٌ دائم على حقلٍ ماليّ. (رُصد بالتشغيل:
    //  A=100 ثم B=250 ثم A→100 ⇒ يبقى الخادم 250.)
    //
    //  ولا يُعيد هذا عطل v27 (لقطةٌ تحمل مفتاحاً لا يملكه البعيد فيُقرأ
    //  حذفاً): هناك كانت القيمة **غير مدفوعة**، وهنا مدفوعةٌ ومُقرّة —
    //  فالخادم يحملها فعلاً، وغيابها لاحقاً من دفع جهازٍ آخر حذفٌ حقيقي لا
    //  زائف. والشرط `stillSame` يمنع تثبيت قيمةٍ عُدّل الصف بعدها.
    if (stillSame) {
      setShadow(ctx.db, entity, id, splitSyncColumns(local).domain);
    }
  } catch (_) {/* best-effort */}
}

class PushResult {
  const PushResult({
    required this.pushed,
    required this.failed,
    required this.attempted,
    required this.hasMore,
  });

  final int pushed;
  final int failed;
  final int attempted;
  final bool hasMore;
}

/// Drain dirty rows to the server once.
Future<PushResult> pushOnce(SyncContext ctx) async {
  final quarantined =
      getMetaJson<List>(ctx.db, quarantineKey, const []).toSet();

  // Collect dirty rows across all entities, skipping quarantined ids.
  var candidates = <({String entity, Row row})>[];
  for (final entity in syncEntities) {
    for (final row in getDirtyRows(ctx.db, entity)) {
      if (quarantined.contains(_keyOf(entity, row['id']))) continue;
      candidates.add((entity: entity, row: row));
    }
  }
  if (candidates.isEmpty) {
    return const PushResult(pushed: 0, failed: 0, attempted: 0, hasMore: false);
  }

  // Oldest first (causal order).
  candidates.sort((a, b) =>
      jsNumOr0(a.row['_mod']).compareTo(jsNumOr0(b.row['_mod'])));
  final totalCandidates = candidates.length;
  candidates = candidates.take(batchLimit).toList();

  final ops = <WireOp>[];
  for (final c in candidates) {
    ensureHlc(ctx, c.entity, c.row);
    ops.add(buildOp(ctx, c.entity, c.row));
  }

  final attempts = Map<String, Object?>.from(
      getMetaJson<Map>(ctx.db, attemptsKey, const {}));

  var pushed = 0;
  try {
    final results = await ctx.transport.applyChanges(ops);
    final byOp = {for (final o in ops) o.opId: o};
    for (final res in results) {
      final op = byOp[res.opId];
      if (op == null) continue;
      markRowSynced(ctx, op.entity, res.id, res.serverSeq, op.pushedHlc);
      attempts.remove(_keyOf(op.entity, res.id));
      pushed++;
    }
    setMetaJson(ctx.db, attemptsKey, attempts);
    return PushResult(
      pushed: pushed,
      failed: 0,
      attempted: ops.length,
      hasMore: totalCandidates > candidates.length,
    );
  } catch (e) {
    // Bump per-row attempts; quarantine only after MAX_ATTEMPTS. Rows stay
    // `_dirty = 1` — nothing is ever auto-deleted.
    final qSet = getMetaJson<List>(ctx.db, quarantineKey, const [])
        .cast<Object?>()
        .toSet();
    for (final op in ops) {
      final k = _keyOf(op.entity, op.row['id']);
      final n = (jsNumOr0(attempts[k])).toInt() + 1;
      attempts[k] = n;
      if (n >= maxAttempts) qSet.add(k);
    }
    setMetaJson(ctx.db, attemptsKey, attempts);
    setMetaJson(ctx.db, quarantineKey, qSet.toList());
    throw Exception('push failed: $e');
  }
}

/// Count of rows waiting to sync (dirty, excluding quarantined).
int getPendingCount(SyncContext ctx) {
  final quarantined =
      getMetaJson<List>(ctx.db, quarantineKey, const []).toSet();
  var n = 0;
  for (final entity in syncEntities) {
    for (final row in getDirtyRows(ctx.db, entity)) {
      if (!quarantined.contains(_keyOf(entity, row['id']))) n++;
    }
  }
  return n;
}

/// Count of rows parked in quarantine (needs manual attention).
int getQuarantinedCount(SyncContext ctx) =>
    getMetaJson<List>(ctx.db, quarantineKey, const []).length;

/// Clear quarantine so parked rows are retried on the next cycle.
void retryQuarantined(SyncContext ctx) {
  setMetaJson(ctx.db, quarantineKey, const []);
  setMetaJson(ctx.db, attemptsKey, const {});
}
