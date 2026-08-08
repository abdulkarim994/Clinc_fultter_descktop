/// ============================================================================
///  Conflict resolution + additive merge — literal port of sync/conflict.js
/// ============================================================================
///
///  Applies a remote row pulled from the server into the local repositories.
///    - HLC last-writer-wins at row granularity (LEGACY path, default).
///    - Flag-gated STRUCTURE-DRIVEN field-level merge in parallel; verify mode
///      maintains the shadow + logs divergences without changing data.
///    - `settings` = per-key HLC LWW; `app.config` decomposed when enabled.
///    - A dirty local row is NEVER clobbered unless the remote is strictly newer.
///    - NO destructive path: deletes are soft tombstones through the same
///      comparison; every discarded local value lands in `conflict_log`.
library;

import 'dart:convert';

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'context.dart';
import 'db_sync.dart';
import 'entities.dart';
import 'feature_flags.dart';
import 'hlc.dart' show isNewer;
import 'merge/config_merge.dart';
import 'merge/field_merge.dart';
import 'merge/merge_engine.dart' show deepEqual;
import 'merge/shadow_store.dart';
import 'merge/tombstones.dart';

/// Strip transport-only props and force server-origin (`_dirty = 0`).
Row asServerRecord(Row remote) {
  final rec = Map<String, Object?>.from(remote);
  rec.remove('_entity');
  rec.remove('data'); // merged fields already spread; avoid stale blob
  rec['_dirty'] = 0;
  rec['_deleted'] = jsNumber(remote['_deleted']) == 1 ? 1 : 0;
  return rec;
}

/// م21 — الكيانات ذات عمودَي ربط المريض المرقَّيين.
const Set<String> patientLinkedEntities = {
  'records', 'prosthetics', 'debts', 'appointments', 'xrays', 'queue_patients',
};

/// م21 — تطبيع صف الخادم قبل الكتابة: كائنات Vue تحمل اسم المريض في حقل
/// `name` (كتلة الـ blob) ولا تملأ عمود `patient_name` إطلاقاً — فتصل صفوف
/// الحساب (القديمة وحتى كتابات Vue الجارية) بعمود ربط فارغ: التجميعات
/// الذاكريّة تراها (تقرأ name المدموج) بينما استعلامات القوائم
/// `WHERE patient_name = ?` تخفيها («مسجّل أعلى الملف وما ظاهر بالسجل»).
/// نشتق `patient_name` من `name` عند غيابه، و`patient_id` بمفتاح الاسم
/// القديم عند غيابه — **لا نلمس قيمة حاضرة أبداً** (مفاتيح الهوية الهاتفية
/// القادمة من الأصل تمر كما هي). توأم backfill الهجرات لكن لصفوفٍ تصل
/// بعد فتح القاعدة عبر المزامنة.
Row normalizeServerRow(String entity, Row rec) {
  String t(Object? v) => '${v ?? ''}'.trim();
  if (patientLinkedEntities.contains(entity)) {
    final name = t(rec['name']);
    if (t(rec['patient_name']).isEmpty && name.isNotEmpty) {
      rec['patient_name'] = name;
    }
    final link = t(rec['patient_name']);
    if (t(rec['patient_id']).isEmpty && link.isNotEmpty) {
      rec['patient_id'] = link;
    }
  } else if (entity == 'patients') {
    final name = t(rec['name']);
    if (t(rec['patient_id']).isEmpty && name.isNotEmpty) {
      rec['patient_id'] = name;
    }
  }
  return rec;
}

/// Merge one pulled remote row into local. Never deletes local data.
/// Returns: inserted | updated | merged | kept-local | noop.
String mergeRemoteRow(SyncContext ctx, String entity, Row? remote) {
  if (remote == null || remote['id'] == null || remote['id'] == '') {
    return 'noop';
  }
  ctx.receive(remote['_hlc'] as String?);

  if (entity == 'settings') return _mergeSetting(ctx, remote);

  final repo = repoFor(ctx, entity);
  if (repo == null) return 'noop';

  final id = remote['id'] as String;
  final local = getRowRaw(ctx.db, entity, id);

  // ── Field-level merge (PARALLEL, flag-gated) ─────────────────────────────
  final fmOn = isFieldMergeEnabled(entity);
  final fmVerify = isFieldMergeVerifyEnabled();
  if (fmOn || fmVerify) {
    try {
      final shadow = getShadow(ctx.db, entity, id);
      final plan = planFieldMerge(
        entity: entity,
        local: local,
        remote: remote,
        shadow: shadow,
        isNewer: isNewer,
        tick: (_) => ctx.tick(),
        deviceId: ctx.deviceId,
      );
      // v27 — تقدّم لقطة الأساس **فقط عند استيعاب حالة أجنبية فعلاً**
      // (inserted/updated/merged). كان التقدّم يحدث أيضاً على «صدى دفعنا
      // نحن» (noop/kept-local) فتصير قيمتنا غير المشتركة أساساً مشتركاً
      // زائفاً ⇒ غيابها من دفع الجهاز الآخر يُقرأ حذفاً فتُمسح بياناتنا.
      if (plan.status != 'noop' && plan.status != 'kept-local') {
        applyShadowPlan(ctx.db, entity, id, plan.baseline);
      }

      if (fmVerify && !fmOn) {
        final legacy = legacyDecision(local, remote, isNewer);
        final planDomain = planEffectiveDomain(plan, local);
        if (!deepEqual(planDomain, legacy.domain)) {
          // verify mode: divergences observable via the conflict log channel.
          _logDivergence(ctx, entity, id, plan.status, legacy.status);
        }
        // verify never applies the new result — fall through to legacy.
      }

      if (fmOn) {
        if (plan.row == null) return plan.status;
        logConflict(ctx.db, entity, local, remote);
        // Record each newly-converged item tombstone's birth seq so compaction
        // can later prove it is safe to prune. Idempotent; no-op without seq.
        final rowToWrite = Map<String, Object?>.from(
            stampTombstoneSeqs(entity, plan.row, remote['server_seq'])
                as Map);
        repo.upsert(normalizeServerRow(entity, rowToWrite));
        return plan.status;
      }
    } catch (_) {
      // fall through to the legacy path — never break sync.
    }
  }

  // ── Legacy row-LWW path (unchanged) ──────────────────────────────────────
  if (local == null) {
    repo.upsert(normalizeServerRow(entity, asServerRecord(remote)));
    return 'inserted';
  }

  // Local has un-pushed edits and is not older → local wins, stays queued.
  if (jsNumber(local['_dirty']) == 1 &&
      !isNewer(remote['_hlc'] as String?, local['_hlc'] as String?)) {
    return 'kept-local';
  }

  if (isNewer(remote['_hlc'] as String?, local['_hlc'] as String?)) {
    logConflict(ctx.db, entity, local, remote);
    repo.upsert(normalizeServerRow(entity, asServerRecord(remote)));
    return 'updated';
  }
  return 'noop';
}

final List<String> divergenceLog = <String>[]; // test-observable verify channel

void _logDivergence(
    SyncContext ctx, String entity, String id, String p, String l) {
  divergenceLog.add('$entity/$id: new=$p legacy=$l');
}

bool _isDeletedRow(Row? row) => row != null && jsNumber(row['_deleted']) == 1;

/// Settings merge — per-key whole-value HLC LWW; `app.config` decomposed
/// field-merge when enabled for `settings`.
String _mergeSetting(SyncContext ctx, Row remote) {
  final id = remote['id'] as String;
  final local = getRowRaw(ctx.db, 'settings', id);

  // ── app.config decomposed field-merge (flag-gated, additive) ─────────────
  if (id == 'app.config' &&
      isFieldMergeEnabled('settings') &&
      !_isDeletedRow(remote) &&
      !_isDeletedRow(local)) {
    try {
      final shadow = getShadow(ctx.db, 'settings', id);
      final plan = planConfigMerge(
        local: local != null ? decodeConfigValue(local['value']) : null,
        remote: decodeConfigValue(remote['value']),
        base: shadow,
        localHlc: local?['_hlc'] as String?,
        remoteHlc: remote['_hlc'] as String?,
        isNewer: isNewer,
        tick: (_) => ctx.tick(),
        deviceId: ctx.deviceId,
      );
      // v27 — نفس قاعدة الأساس المحافِظة (انظر مسار الصفوف أعلاه).
      if (plan.status == 'noop' || plan.status == 'kept-local') {
        return plan.status;
      }
      applyShadowPlan(ctx.db, 'settings', id, plan.baseline);
      if (local != null) logConflict(ctx.db, 'settings', local, remote);
      if (plan.status == 'merged') {
        // Genuine blend: persist merged config DIRTY with a fresh HLC → push.
        _putSettingLocal(ctx,
            id: id,
            value: plan.value,
            clinicId: remote['clinic_id'] as String?,
            hlc: plan.hlc,
            origin: ctx.deviceId);
        return 'merged';
      }
      // status == 'updated' → accept the server config wholesale.
      _putSettingServer(ctx, {...remote, 'value': plan.value});
      return 'updated';
    } catch (e) {
      // v27 — كان السقوط صامتاً: أي استثناء هنا يعيدنا للحسم بالساعة
      // الأحدث (فقدان صامت محتمل لعمل الجهاز الآخر). نسجّله في قناة
      // الانحراف القابلة للفحص بدل ابتلاعه.
      divergenceLog
          .add('settings/app.config: field-merge failed → LWW ($e)');
    }
  }

  // ── Legacy per-key whole-value HLC LWW (unchanged) ───────────────────────
  if (local != null &&
      jsNumber(local['_dirty']) == 1 &&
      !isNewer(remote['_hlc'] as String?, local['_hlc'] as String?)) {
    return 'kept-local';
  }
  if (local != null &&
      !isNewer(remote['_hlc'] as String?, local['_hlc'] as String?)) {
    return 'noop';
  }
  if (local != null) logConflict(ctx.db, 'settings', local, remote);
  _putSettingServer(ctx, remote);
  return local != null ? 'updated' : 'inserted';
}

/// Write a merged setting row as a LOCAL dirty change with an explicit fresh
/// HLC, so the blended app.config is queued for push.
void _putSettingLocal(
  SyncContext ctx, {
  required String id,
  required Object? value,
  String? clinicId,
  String? hlc,
  String? origin,
}) {
  final encoded = jsonEncode(value);
  final cid = clinicId ?? '';
  final owner = ctx.db.getOwnerUid();
  ctx.db.execute(
    'INSERT INTO settings (id, clinic_id, value, updated_at, _mod, _hlc, _dirty, _origin, _deleted, owner_uid) '
    "VALUES (?, ?, ?, datetime('now'), ?, ?, 1, ?, 0, ?) "
    'ON CONFLICT(id) DO UPDATE SET value = ?, clinic_id = ?, '
    "updated_at = datetime('now'), "
    '_mod = ?, _hlc = ?, _dirty = 1, _origin = ?, _deleted = 0, '
    'owner_uid = COALESCE(?, owner_uid)',
    [
      id, cid, encoded, jsNow(), hlc, origin, owner, //
      encoded, cid, jsNow(), hlc, origin, owner,
    ],
  );
}

/// Write a server-origin setting row (`_dirty = 0`), tombstone-aware.
/// ACCOUNT ISOLATION: stamped with the active owner (RLS already scoped the
/// server rows to this account) so pulled settings can never leak cross-account.
void _putSettingServer(SyncContext ctx, Row remote) {
  final id = remote['id'] as String;
  final encoded = jsonEncode(remote['value']);
  final clinicId = (remote['clinic_id'] as String?) ?? '';
  final hlc = remote['_hlc'] as String?;
  final origin = remote['_origin'] as String?;
  final del = jsNumber(remote['_deleted']) == 1 ? 1 : 0;
  final owner = ctx.db.getOwnerUid();
  ctx.db.execute(
    'INSERT INTO settings (id, clinic_id, value, updated_at, _mod, _hlc, _dirty, _origin, _deleted, owner_uid) '
    "VALUES (?, ?, ?, datetime('now'), ?, ?, 0, ?, ?, ?) "
    'ON CONFLICT(id) DO UPDATE SET value = ?, clinic_id = ?, '
    "updated_at = datetime('now'), "
    '_mod = ?, _hlc = ?, _dirty = 0, _origin = ?, _deleted = ?, '
    'owner_uid = COALESCE(?, owner_uid)',
    [
      id, clinicId, encoded, jsNow(), hlc, origin, del, owner, //
      encoded, clinicId, jsNow(), hlc, origin, del, owner,
    ],
  );
}

/// Best-effort audit: persist the value about to be overwritten (recoverable).
void logConflict(LocalDb db, String entity, Row? local, Row remote) {
  try {
    db.execute(
      'INSERT INTO conflict_log (entity, entity_id, local_json, remote_json, resolved_to, created_at) '
      "VALUES (?, ?, ?, ?, ?, datetime('now'))",
      [
        entity,
        remote['id'],
        jsonEncode(local),
        jsonEncode(remote),
        'remote',
      ],
    );
  } catch (_) {/* non-fatal — audit must never block a merge */}
}
