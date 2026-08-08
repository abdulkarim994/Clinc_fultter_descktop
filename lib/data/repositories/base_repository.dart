/// ============================================================================
///  Base Repository — literal Dart port of repositories/base.repository.js
/// ============================================================================
///
///  The JS original routed between two backends (native SQLite / IndexedDB).
///  The Flutter build has exactly ONE backend (SQLite via LocalDb), so every
///  `isUsingSQLite()` branch collapses to the native path — the IDB fallbacks
///  are intentionally gone, not forgotten.
///
///  Account isolation, tombstone semantics, dirty/HLC stamping and keyset
///  pagination are preserved 1:1.
library;

import 'intent_row_merge.dart';
import '../db/local_db.dart';
import '../sync/merge/row_fmeta.dart' show stampRowFields;

/// Keyset pagination cursor — `{value, id}` of the last row of the previous
/// page (exclusive).
typedef PageCursor = ({Object? value, String id});

class PageResult {
  const PageResult({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Row> items;
  final PageCursor? nextCursor;
  final bool hasMore;
}

final _identRe = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

class BaseRepository {
  BaseRepository(this.db, this.tableName, this.knownColumns);

  final LocalDb db;

  /// SQLite table name.
  final String tableName;

  /// Columns that exist in the SQLite schema (everything else is serialized
  /// into the `data` blob by prepareForStorage).
  final List<String> knownColumns;

  /// م65 — مرادفات الحقول: الاسم بصيغة camelCase ⇒ العمود الحقيقي.
  ///
  /// العلة التي يعالجها: مسارات المال في الديون تكتب `paidAmount` و
  /// `totalAmount`/`total` (وهي أسماء **ليست أعمدة**)، فيوجّهها
  /// `prepareForStorage` إلى كتلة `data` بينما يبقى العمودان الحقيقيان
  /// `paid_amount` و`total_amount` على قيمتهما الأولى إلى الأبد. النتيجة
  /// أن العمود يقول 200 والكتلة تقول 500 — و**الحمولة المدفوعة تحمل
  /// القيمتين المتناقضتين معاً** فتسافران إلى كل الأجهزة، وأي تقرير SQL
  /// يقرأ العمود يكون مخطئاً بكامل تاريخ الدفعات.
  ///
  /// الحل هنا لا في مواضع الاستدعاء: أي كتابة لاسم مرادف تُسقَط أيضاً على
  /// عمودها الحقيقي قبل التقسيم، فتبقى الصيغتان متطابقتين دائماً مهما كان
  /// المصدر (تطبيق Flutter أو صفوف Vue القديمة).
  /// الترتيب مقصود: `total` قبل `totalAmount` كي يفوز الاسم الأدق عند
  /// حضورهما معاً (وهما متساويان في كل مسارات الكتابة أصلاً).
  static const Map<String, String> _columnAliases = {
    'paidAmount': 'paid_amount',
    'total': 'total_amount',
    'totalAmount': 'total_amount',
  };

  /// يُسقط المرادفات على أعمدتها الحقيقية.
  ///
  /// **المرادف يفوز عند حضوره**، لا العمود. السبب أن `getById` يعيد رؤية
  /// مدموجة تحوي العمود دائماً، فلو قدّمنا العمود لما سرى المرادف أبداً —
  /// وهو بالضبط ما يجعل العمود يتجمّد اليوم. ومنطق الأعمال في هذا المشروع
  /// يعدّل صيغة camelCase (`debt['paidAmount'] = ... + amount`)، فهي
  /// القيمة الطازجة والعمود هو الأثر القديم.
  ///
  /// الصفوف التي تكتب العمود وحده (صفوف الخادم مثلاً) لا تحمل المرادف
  /// فلا يمسّها هذا الإسقاط.
  Row applyColumnAliases(Row record) {
    Map<String, Object?>? out;
    for (final e in _columnAliases.entries) {
      if (!record.containsKey(e.key)) continue;
      if (!knownColumns.contains(e.value)) continue;
      final v = record[e.key];
      if (v == null) continue; // لا نمسح عموداً بقيمة غائبة
      (out ??= Map<String, Object?>.from(record))[e.value] = v;
    }
    return out ?? record;
  }

  /// Stamp the owner uid onto a record for storage (never overwrites a set,
  /// foreign owner — mirror of `_withOwner`).
  Row withOwner(Row record) {
    final owner = db.getOwnerUid();
    if (owner == null) return record;
    final existing = record['owner_uid'];
    if (existing != null && existing != '' && existing != owner) {
      return record; // foreign row, leave as-is
    }
    return {...record, 'owner_uid': owner};
  }

  /// Get all non-deleted records.
  List<Row> getAll() {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM $tableName WHERE _deleted = 0${oc.sql}',
      oc.params,
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Get ALL records including soft-deleted tombstones (used by sync/backfill
  /// paths that must know about deleted rows to prevent resurrection).
  List<Row> getAllIncludingDeleted() {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM $tableName WHERE 1 = 1${oc.sql}',
      oc.params,
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Account-scoped ids of soft-deleted rows (tombstones) — the AUTHORITATIVE
  /// deletion signal for the read-path projection.
  List<String> getDeletedIds() {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT id FROM $tableName WHERE _deleted = 1${oc.sql}',
      oc.params,
    );
    return [
      for (final r in rows)
        if (r['id'] is String && (r['id'] as String).isNotEmpty)
          r['id'] as String,
    ];
  }

  /// Get a single record by ID.
  Row? getById(String id) => parseRowData(db.getById(tableName, id));

  /// Insert or update a single record.
  void upsert(Row record) {
    final id = record['id'];
    if (id == null || id == '') return;
    final stamped = withOwner(applyColumnAliases(record));
    final row = prepareForStorage(stamped, knownColumns);
    db.upsertRecord(tableName, row, knownColumns);
  }

  /// Partial update: merges updates into the existing record then upserts.
  ///
  /// ⚠ يمرّ عبر [upsert] الذي **لا يختم** `_dirty`/`_hlc`/`_origin` — أي أن
  /// التعديل لا يدخل طابور الدفع فلا يتزامن. مناسبٌ فقط للكتابة الصادرة من
  /// الخادم (تطبيع). للتعديل المحلي الذي يجب أن يتزامن استعمل [updateLocal].
  Row? update(String id, Row updates) {
    final existing = getById(id);
    if (existing == null) return null;
    final merged = {...existing, ...updates, 'id': id};
    upsert(merged);
    return merged;
  }

  /// م-إصلاح — تعديل جزئي **محلّي يتزامن**: يدمج [updates] فوق الصف القائم
  /// ويمرّ عبر [upsertLocal] مع تمرير `base: existing` — فيُختم `_dirty=1`
  /// و`_hlc` وتُدَقّ ساعات الحقول المتغيّرة، ويدخل التعديل طابور المزامنة،
  /// ويُحسم الدمج الحقلي الثلاثي فلا يمسح تعديلَ جهازٍ آخر على حقلٍ مختلف.
  /// (نظير [update] لكنه المسار الصحيح لأي تحرير من الواجهة.)
  Row? updateLocal(String id, Row updates) {
    final existing = getById(id);
    if (existing == null) return null;
    final merged = {...existing, ...updates, 'id': id};
    upsertLocal(merged, base: existing);
    return merged;
  }

  /// Bulk insert/update records (one transaction).
  void bulkUpsert(List<Row> records) {
    if (records.isEmpty) return;
    final rows = [
      for (final r in records)
        if (r['id'] != null && r['id'] != '')
          // م84 — `applyColumnAliases` كان مفقوداً هنا وحاضراً في `upsert`
          // المفرد. بدونه تهبط المفاتيح camelCase (‏totalAmount…) في مدونة
          // `data` وحدها بينما تبقى الأعمدة الحقيقية صفراً، فيقرأ أي SQL
          // على العمود قيمةً خاطئة. لا مسار شحن يجمّع الديون/السجلات اليوم،
          // لكن أول استيراد جماعي من كائنات المجال يُصيب — وهو عينُ صنف
          // العطل (isDebt) الذي أُصلح سابقاً. الاتّساق مع المفرد يسدّه.
          prepareForStorage(withOwner(applyColumnAliases(r)), knownColumns),
    ];
    db.bulkUpsert(tableName, rows, knownColumns);
  }

  /// Soft-delete a record: writes a tombstone (`_deleted = 1`) stamped
  /// `_dirty = 1` with a fresh HLC + device origin so the delta sync engine
  /// PROPAGATES the delete. The row is kept ("no hard delete" invariant).
  void delete(String id) {
    if (id.isEmpty) return;
    final existing = getById(id);
    if (existing != null) {
      final stamped = {
        ...existing,
        '_deleted': 1,
        '_dirty': 1,
        '_hlc': db.hlc.tick(db.deviceId),
        '_origin': db.deviceId,
        '_mod': DateTime.now().millisecondsSinceEpoch,
      };
      upsert(stamped);
      db.kickSync();
      return;
    }
    // v32 — «الحذف ينتشر دائماً»: الصف غير الموجود محلياً (لم يصل بعد
    // من المزامنة، أو محذوف سلفاً) كان يسقط إلى تحديث صامت بلا شاهد ولا
    // _dirty — فيضيع الحذف ويعود الصف حياً عند وصوله. الآن يُكتب شاهد
    // قبر قذر بساعة جديدة ينتشر لكل الأجهزة حتماً.
    final tomb = <String, Object?>{
      'id': id,
      '_deleted': 1,
      '_dirty': 1,
      '_hlc': db.hlc.tick(db.deviceId),
      '_origin': db.deviceId,
      '_mod': DateTime.now().millisecondsSinceEpoch,
    };
    upsert(tomb);
    db.kickSync();
  }

  /// Precise per-action local write: upsert a record stamped `_dirty = 1` with
  /// a fresh HLC + origin, then kick a sync. UI write paths use this;
  /// server-origin writes must keep using [upsert].
  /// v31 — كتابة محلية **مطابقة لنيّة المستخدم**: عند تمرير [base] (لقطة
  /// الصف التي بنت عليها الواجهة تعديلها) تُطبَّق الحقول التي تغيّرت فعلاً
  /// فقط فوق الصف المخزّن الآن. بدونها كانت الكتابة تُرسل الصف كاملاً
  /// بساعة جديدة، فأي حقل عدّله جهاز آخر ووصل بين القراءة والحفظ يعود
  /// لقيمته القديمة ⇒ «جهاز يمسح تعديل الآخر».
  void upsertLocal(Row record, {Row? base}) {
    final id = record['id'];
    if (id == null || id == '') return;
    var record0 = record;
    if (base != null) {
      final stored = getById('$id');
      if (stored != null) {
        record0 = mergeIntentRow(
          stored: Map<String, Object?>.from(stored),
          base: Map<String, Object?>.from(base),
          incoming: Map<String, Object?>.from(record),
        );
      }
    }
    final hlc = db.hlc.tick(db.deviceId);
    var stamped = <String, Object?>{
      ...record0,
      '_dirty': 1,
      '_hlc': hlc,
      '_origin': db.deviceId,
      '_mod': DateTime.now().millisecondsSinceEpoch,
    };
    // م81 — ختم ساعات الحقول المتغيّرة.
    //
    // بلا هذا الختم يُحسم كل حقل متعارض بساعة **الصف كلّه**، فتعديلان
    // متزامنان على حقلين مختلفين يجعل أحدهما يختفي بصمت بحسب ترتيب
    // الوصول. الختم هنا — في منفذ الكتابة الوحيد — يجعل الدمج يحسم كل
    // حقل بساعة الجهاز الذي لمسه فعلاً.
    //
    // يُقرأ المخزَّن للمقارنة: الحقل الذي لم تتغيّر قيمته لا يُختَم، وإلا
    // فاز جهازٌ بحقلٍ لم يمسّه.
    try {
      stamped = stampRowFields(getById('$id'), stamped, hlc);
    } catch (_) {/* أفضل جهد — الختم تحسين لا شرط صحة */}
    // م21 — اشتقاق عمودَي ربط المريض عند الكتابة المحلية (توأم تطبيع
    // الدمج normalizeServerRow في conflict): كائنات الواجهة تحمل الاسم في
    // حقل `name` وحده؛ ملء العمودين هنا يوحّد شكل الصف بين الجهاز الكاتب
    // والجهاز الساحب (تقارب بايتاً-ببايت) ويجعل استعلامات القوائم
    // `WHERE patient_name = ?` ترى الكتابات فوراً. لا نمس قيمة حاضرة.
    String t(Object? v) => '${v ?? ''}'.trim();
    if (knownColumns.contains('patient_name') &&
        t(stamped['patient_name']).isEmpty &&
        t(stamped['name']).isNotEmpty) {
      stamped['patient_name'] = t(stamped['name']);
    }
    if (knownColumns.contains('patient_id') &&
        t(stamped['patient_id']).isEmpty) {
      final link = knownColumns.contains('patient_name')
          ? t(stamped['patient_name'])
          : t(stamped['name']);
      if (link.isNotEmpty) stamped['patient_id'] = link;
    }
    upsert(stamped);
    db.kickSync();
  }

  /// Mark an existing row dirty by id (e.g. after an out-of-band change).
  void markDirty(String id) {
    final existing = getById(id);
    if (existing == null) return;
    upsertLocal(existing);
  }

  /// Records modified after [timestamp] (for sync).
  List<Row> getModifiedSince(int timestamp) {
    final rows = db.getModifiedSince(tableName, timestamp);
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Total count of non-deleted records.
  int count() {
    final oc = db.ownerClause();
    final result = db.queryFirst(
      'SELECT COUNT(*) as cnt FROM $tableName WHERE _deleted = 0${oc.sql}',
      oc.params,
    );
    return (result?['cnt'] as int?) ?? 0;
  }

  /// Keyset (seek) pagination over an indexed column — literal port of
  /// getPage(): one page ordered by `(orderBy, id)` with a strict keyset
  /// predicate instead of OFFSET, `id` as the stable tie-breaker, and one
  /// extra row fetched to detect `hasMore` without a COUNT.
  PageResult getPage({
    String orderBy = 'date',
    String dir = 'DESC',
    int limit = 50,
    PageCursor? cursor,
    String where = '',
    List<Object?> whereParams = const [],
  }) {
    // orderBy/where are code-controlled, never user input. Whitelisted as
    // defence-in-depth against accidental injection.
    if (!_identRe.hasMatch(orderBy)) {
      throw ArgumentError("getPage: invalid orderBy '$orderBy'");
    }
    final lim = limit < 1 ? 50 : limit;
    final dirSql = dir == 'ASC' ? 'ASC' : 'DESC';
    final cmp = dirSql == 'ASC' ? '>' : '<';
    final oc = db.ownerClause();
    final clauses = <String>['_deleted = 0'];
    final params = <Object?>[];
    if (where.isNotEmpty) {
      clauses.add('($where)');
      params.addAll(whereParams);
    }
    if (oc.sql.isNotEmpty) {
      clauses.add(oc.sql.replaceFirst(RegExp(r'^\s*AND\s*'), ''));
      params.addAll(oc.params);
    }
    if (cursor != null && cursor.value != null) {
      clauses.add('($orderBy $cmp ? OR ($orderBy = ? AND id $cmp ?))');
      params
        ..add(cursor.value)
        ..add(cursor.value)
        ..add(cursor.id);
    }
    final sql = 'SELECT * FROM $tableName WHERE ${clauses.join(' AND ')} '
        'ORDER BY $orderBy $dirSql, id $dirSql LIMIT ?';
    params.add(lim + 1); // one extra row to detect hasMore without a COUNT
    final rows = db.query(sql, params);
    final hasMore = rows.length > lim;
    final page = [
      for (final r in (hasMore ? rows.sublist(0, lim) : rows)) parseRowData(r)!,
    ];
    final last = page.isEmpty ? null : page.last;
    final nextCursor = last == null
        ? null
        : (value: last[orderBy], id: last['id'] as String);
    return PageResult(items: page, nextCursor: nextCursor, hasMore: hasMore);
  }
}
