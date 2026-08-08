/// ============================================================================
///  PULL — literal port of sync/pull.js (pull_changes → local repositories)
/// ============================================================================
///
///  ONE global cursor: a COMMIT-safe txid watermark. Each drain pages rows with
///  txid in [cursor, safe) by the (txid, server_seq) keyset — `safe` PINNED
///  from the first page so the window can't shift — and advances the durable
///  cursor to `safe` ONLY after the window is fully drained. A crash mid-drain
///  just re-drains the same window (merge is idempotent via HLC).
library;

import '../db/local_db.dart';
import 'conflict.dart';
import 'context.dart';
import 'db_sync.dart';
import 'merge/compaction.dart';
import 'merge/tombstones.dart' show compactionHorizonKey;
import 'transport.dart';

const cursorKey = 'sync.cursor.txid';

/// م73 — أعلى txid حُذف بالأرشفة الباردة على الخادم. يكتبه السحب ويقرؤه
/// مشغّل الأرشفة لكشف فجوة هذا الجهاز.
const archiveHorizonKey = 'sync.archive.horizon';
const pageSize = 500;

/// Rebuild a local-shaped row from a `sync_rows` record.
Row reconstruct(PullRow sr) {
  return {
    ...sr.payload,
    'id': sr.id,
    'clinic_id': sr.clinicId ?? sr.payload['clinic_id'],
    '_hlc': sr.hlc,
    '_deleted': sr.deleted ? 1 : 0,
    '_origin': sr.origin,
    'server_seq': sr.serverSeq,
    '_entity': sr.entity,
  };
}

/// Merge one pulled page. On native the whole page commits in ONE transaction;
/// on failure it rolls back and re-applies row-by-row (never loses/skips).
int mergePage(SyncContext ctx, List<PullRow> rows) {
  try {
    ctx.db.execute('BEGIN');
    try {
      var merged = 0;
      for (final sr in rows) {
        if (sr.entity.isEmpty || sr.id.isEmpty) continue;
        mergeRemoteRow(ctx, sr.entity, reconstruct(sr));
        merged++;
      }
      ctx.db.execute('COMMIT');
      return merged;
    } catch (_) {
      try {
        ctx.db.execute('ROLLBACK');
      } catch (_) {/* ignore */}
      // fall through to the row-by-row path
    }
  } catch (_) {/* transaction unsupported — row-by-row */}
  var merged = 0;
  for (final sr in rows) {
    if (sr.entity.isEmpty || sr.id.isEmpty) continue;
    mergeRemoteRow(ctx, sr.entity, reconstruct(sr));
    merged++;
  }
  return merged;
}

class PullResult {
  const PullResult(
      {required this.merged, required this.batches, required this.cursor});

  final int merged;
  final int batches;
  final int cursor;
}

/// Pull every change up to the server's commit-safe watermark and merge it.
Future<PullResult> pullOnce(SyncContext ctx) async {
  final lower =
      (num.tryParse('${getMetaValue(ctx.db, cursorKey) ?? ''}') ?? 0).toInt();
  var merged = 0;
  var batches = 0;
  int? pageTxid; // keyset position within the pinned window
  var pageSeq = 0;
  int? upto; // pinned safe watermark for this drain

  for (;;) {
    final page = await ctx.transport.pullChanges(
      lower: lower,
      pageTxid: pageTxid,
      pageSeq: pageSeq,
      upto: upto,
      limit: pageSize,
    );
    final rows = page.rows;
    upto ??= page.safe;

    // م65 — أفق الضغط من الخادم: أدنى مؤشر طبّقته **كل** أجهزة الحساب.
    // تخزينه هنا هو ما يُحيي `runCompaction` أدناه — كانت وحدة الضغط شيفرة
    // ميتة لأن هذا المفتاح لا يكتبه أي موضع في المشروع، فلا تُقلَّم شاهدة
    // أبداً وتتراكم داخل كتل الصفوف إلى الأبد.
    //
    // لا يُكتب إلا أفق موجب يتقدّم للأمام: تراجعه (خادم استُعيد من نسخة
    // احتياطية) لا يجوز أن يوسّع نطاق التقليم.
    final h = page.horizon;
    if (h != null && h > 0) {
      final prev = num.tryParse(
              '${getMetaValue(ctx.db, compactionHorizonKey) ?? ''}') ??
          0;
      if (h > prev) setMetaValue(ctx.db, compactionHorizonKey, '$h');
    }

    // م73 — أفق الأرشيف (غير أفق الضغط أعلاه): أعلى txid حُذف بالأرشفة
    // الباردة. يُخزَّن هنا فقط؛ من يقرؤه هو مشغّل الأرشفة الذي يقارنه
    // بمؤشرنا فيكتشف الفجوة ويسترجع تلقائياً — لا نداء شبكة من داخل
    // حلقة السحب الساخنة.
    final ah = page.archiveHorizon;
    if (ah != null && ah > 0) {
      final prevA = num.tryParse(
              '${getMetaValue(ctx.db, archiveHorizonKey) ?? ''}') ??
          0;
      if (ah > prevA) setMetaValue(ctx.db, archiveHorizonKey, '$ah');
    }

    if (rows.isNotEmpty) {
      merged += mergePage(ctx, rows);
      batches++;
      pageTxid = rows.last.txid;
      pageSeq = rows.last.serverSeq;
    }

    // Short page ⇒ the pinned [cursor, safe) window is fully drained.
    if (rows.length < pageSize) {
      if (upto > lower) setMetaValue(ctx.db, cursorKey, '$upto');
      // م21 — مكنسة شفاء ما بعد السحب: صفوف وصلت قبل تطبيع الدمج (أو من
      // نسخ أقدم على هذا الجهاز) قد تحمل عمود ربط فارغاً؛ تحديثات
      // idempotent محروسة (لا تمس قيمة حاضرة) تشتق patient_name/patient_id
      // من كتلة الـ blob — توأم backfill الهجرات لكن بعد كل سحب لا عند
      // الفتح فقط.
      try {
        backfillPulledRows(ctx.db);
      } catch (_) {/* best-effort */}
      // Post-drain, best-effort tombstone compaction (self-guards on horizon).
      try {
        runCompaction(ctx);
      } catch (_) {/* best-effort */}
      return PullResult(merged: merged, batches: batches, cursor: upto);
    }
  }
}

/// م21 — تحديثات الشفاء المحروسة (رخيصة؛ آمنة التكرار). تعالج الجداول
/// الستة ذات ربط المريض + مفتاح المرضى + الأعمدة المالية الساخنة للسجلات
/// (احتياطاً لصفوف بالغة القدم كانت حقولها داخل data وقت الدفع).
void backfillPulledRows(LocalDb db) {
  const linked = [
    'records', 'prosthetics', 'debts', 'appointments', 'xrays',
    'queue_patients',
  ];
  for (final t in linked) {
    db.execute(
        "UPDATE $t SET patient_name = TRIM(json_extract(data,'\$.name')) "
        "WHERE (patient_name IS NULL OR TRIM(patient_name) = '') "
        'AND data IS NOT NULL '
        "AND TRIM(COALESCE(json_extract(data,'\$.name'),'')) <> ''");
    db.execute(
        'UPDATE $t SET patient_id = TRIM(patient_name) '
        "WHERE (patient_id IS NULL OR TRIM(patient_id) = '') "
        "AND TRIM(COALESCE(patient_name,'')) <> ''");
  }
  db.execute(
      'UPDATE patients SET patient_id = TRIM(name) '
      "WHERE (patient_id IS NULL OR TRIM(patient_id) = '') "
      "AND TRIM(COALESCE(name,'')) <> ''");
  db.execute(
      "UPDATE records SET payment = json_extract(data,'\$.payment') "
      'WHERE payment IS NULL AND data IS NOT NULL '
      "AND json_extract(data,'\$.payment') IS NOT NULL");
  db.execute(
      "UPDATE records SET debtId = json_extract(data,'\$.debtId') "
      'WHERE debtId IS NULL AND data IS NOT NULL '
      "AND json_extract(data,'\$.debtId') IS NOT NULL");
  for (final c in ['isDebt', 'isPros', 'isDebtPayment']) {
    db.execute(
        "UPDATE records SET $c = COALESCE(json_extract(data,'\$.$c'), 0) "
        'WHERE $c IS NULL');
  }
}

/// Current pull cursor (commit-safe txid watermark applied locally).
int getCursor(SyncContext ctx) =>
    (num.tryParse('${getMetaValue(ctx.db, cursorKey) ?? ''}') ?? 0).toInt();
