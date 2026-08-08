/// ============================================================================
///  Merge strategy descriptors — literal port of sync/merge/descriptors.js
/// ============================================================================
///
///  DECLARATIVE, STRUCTURE-DRIVEN descriptions consumed by merge_engine.dart.
///  They describe the SHAPE of the data (scalars / objects / arrays-by-id /
///  sets / atomic subtrees), never entity-specific merge procedure.
///
///  Strategy kinds (see mergeNode):
///    - scalar     : field-level 3-way LWW (default for every leaf)
///    - object     : recurse per key; { fields?, default? }
///    - arrayById  : merge array elements by a stable id
///    - set        : order-insensitive union of primitives, 3-way removal aware
///    - atomic|lww : opaque subtree decided whole by row HLC
///
///  Sync/transport columns are handled by the WIRING layer: stripped before
///  the merge and re-stamped after — intentionally NOT domain descriptors.
library;

import 'config_tombs.dart' show kConfigTombsKey;

/// Columns owned by the sync layer — never merged as domain fields.
const Set<String> syncColumns = {
  '_hlc', '_dirty', '_deleted', '_origin', 'server_seq', 'data',
  'owner_uid', '_mod', 'updated_at', 'created_at', '_entity',
};

/// Split a merged row into (domain, meta) so only domain fields are merged.
({Map<String, Object?> domain, Map<String, Object?> meta}) splitSyncColumns(
    Map<String, Object?>? row) {
  final domain = <String, Object?>{};
  final meta = <String, Object?>{};
  if (row != null) {
    for (final e in row.entries) {
      if (syncColumns.contains(e.key)) {
        meta[e.key] = e.value;
      } else {
        domain[e.key] = e.value;
      }
    }
  }
  return (domain: domain, meta: meta);
}

/// Structural merge descriptor — the Dart twin of the JS plain-object shape.
class MergeStrategy {
  const MergeStrategy({
    required this.kind,
    this.fields = const {},
    this.defaultStrategy,
    this.idKey = 'id',
    this.element,
    this.tombstoneKey = '_deleted',
    this.setKeys = const {},
    this.emitTombstones = true,
  });

  final String kind;
  final Map<String, MergeStrategy> fields;
  final MergeStrategy? defaultStrategy;
  final String idKey;
  final MergeStrategy? element;
  final String tombstoneKey;

  /// v27 — أسماء المفاتيح التي قيمتها قائمة قيم بسيطة تُوحَّد اتحاداً
  /// (الأمراض المزمنة مثلاً) داخل شجرة الدمج العميق.
  final Set<String> setKeys;

  /// v27 — هل يكتب المحرك شاهد قبر `{id, _deleted: 1}` عند الحذف؟
  /// الصفوف نعم (منع البعث)، وأشجار الإعدادات لا (توافق Vue).
  final bool emitTombstones;
}

// ── Reusable structural building blocks (SCALAR / OBJECT / ARRAY_BY_ID) ─────
const MergeStrategy scalarStrategy = MergeStrategy(kind: 'scalar');

MergeStrategy objectStrategy([Map<String, MergeStrategy>? fields]) =>
    MergeStrategy(
      kind: 'object',
      fields: fields ?? const {},
      defaultStrategy: scalarStrategy,
    );

/// v27 — دمج بنيوي **عميق** بلا حد: خرائط تُكرَّر مفتاحاً بمفتاح، وقوائم
/// عناصرها كائنات بمعرّفات فريدة تُدمج بالمعرّف (بلا شواهد قبور مكتوبة)،
/// وقوائم [setKeys] تُوحَّد اتحاداً، وما عداها ورقة LWW ثلاثية.
MergeStrategy deepStrategy({
  String idKey = 'id',
  Set<String> setKeys = const {},
  Map<String, MergeStrategy>? fields,
}) =>
    MergeStrategy(
      kind: 'deep',
      idKey: idKey,
      setKeys: setKeys,
      fields: fields ?? const {},
      emitTombstones: false,
    );

MergeStrategy arrayByIdStrategy({String idKey = 'id', MergeStrategy? element}) =>
    MergeStrategy(
      kind: 'arrayById',
      idKey: idKey,
      element: element ?? objectStrategy(),
      tombstoneKey: '_deleted',
    );

/// Default strategy for ANY row entity: a generic object with scalar leaves —
/// two devices editing different flat fields of the same record both survive.
final MergeStrategy defaultEntityStrategy = objectStrategy();

/// Per-entity structural overrides. Absent entities use the default.
///
/// م67/دفعة أول-أ — أُعيد لـ `records` واصفٌ خاص لحقل `report.entries`.
/// كان التعليق السابق يقول إن report يُدمج كقيمة كاملة عمداً وإن واصفه
/// السابق «ثبت أنه ميت» — والسبب الحقيقي أن عناصره كانت **بلا معرّفات**،
/// فلم يجد الاكتشاف التلقائي ما يدمج به. الآن بعد إسناد معرّف ثابت لكل عنصر
/// تقرير عند إنشائه صار الدمج بالمعرّف صحيحاً: طبيبان يوثّقان أسناناً
/// مختلفة في زيارة واحدة ينجو تخطيطهما معاً. أُثبت عملياً أن الاستراتيجية
/// الافتراضية تُرجّح الأحدث كاملاً (يضيع عنصر) بينما هذا الواصف يوحّد بالمعرّف.
final Map<String, MergeStrategy> entityStrategies = {
  // Debts carry an `installments` array of id-bearing payment rows. Merging by
  // id (with durable item tombstones) prevents two devices that each record a
  // payment from clobbering each other, and stops a deleted installment from
  // being resurrected by a stale replica.
  'debts': objectStrategy({
    'installments': arrayByIdStrategy(idKey: 'id'),
  }),
  // Records carry `report` = {entries:[...], meta:{...}} (tooth chart).
  // `entries` are id-bearing since م67; merge by id so concurrent charting on
  // two devices doesn't clobber. Undeclared record fields stay scalar-LWW, and
  // legacy id-less entries fall back to safe whole-value LWW via _allIdentified.
  'records': objectStrategy({
    'report': objectStrategy({
      'entries': arrayByIdStrategy(idKey: 'id'),
    }),
  }),
};

/// Config (`app.config`) decomposed by STRUCTURE so independent settings edited
/// on different devices no longer clobber each other.
final MergeStrategy configStrategy = MergeStrategy(
  kind: 'object',
  defaultStrategy: scalarStrategy, // any unlisted config key → 3-way LWW
  fields: {
    'clinics': const MergeStrategy(kind: 'set'),
    'services': const MergeStrategy(kind: 'set'),
    'payments': const MergeStrategy(kind: 'set'),
    // م48/v27 — الأشجار المتداخلة تُدمج **عميقاً** بلا حد: الدمج القديم
    // كان يفكك المستوى الأول فقط فتبقى قيمة كل مفتاح (نسب عيادة كاملة،
    // خطة مريض كاملة، بطاقة طبية كاملة) ورقةً تُحسم بالساعة الأحدث ⇒
    // جهاز يمسح عمل الآخر. الآن: كل مستوى يُدمج مفتاحاً بمفتاح، ومراحل
    // خطة العلاج تُدمج بمعرّفاتها عنصراً بعنصر (تنجو إضافات الجهازين).
    'clinicRates': deepStrategy(),
    'servicePrices': deepStrategy(),
    'treatmentPlans': deepStrategy(),
    // م18 — تحسين موثَّق فوق الأصل (وصف Vue يُسقطها إلى scalar LWW):
    // السجل الطبي خريطة مفتاحها اسم المريض بنفس شكل treatmentPlans تماماً؛
    // تركها LWW كاملةً يعني أن كتابة طبية على جهاز لم يُكمل أول سحب تمسح
    // سجلات بقية المرضى الطبية. v27: الدمج صار عميقاً فحقول البطاقة نفسها
    // (العمر/الجنس/التشخيص/الملاحظات) تُدمج حقلاً بحقل، والأمراض المزمنة
    // اتحاداً بوعي الحذف.
    'patientMedical': deepStrategy(
        setKeys: const {'chronic', 'chronicDiseases', 'diseases'}),
    'dcConfirm': objectStrategy(),
    // v27 — خريطة شواهد حذف عناصر القوائم: اتحاد محض لا يفقد شاهداً
    // (فقدان الشاهد = بعث مرحلة محذوفة على الجهاز الآخر).
    kConfigTombsKey: const MergeStrategy(kind: 'unionMap'),
    // WhatsApp templates carry NO stable id → atomic subtree (row-HLC LWW);
    // never partially merged, never silently dropped.
    'waTemplates': const MergeStrategy(kind: 'atomic'),
  },
);

/// Resolve the structural strategy for a given sync entity name.
MergeStrategy strategyForEntity(String? entity) =>
    entityStrategies[entity] ?? defaultEntityStrategy;

/// Resolve the strategy for a `settings` row by key: `app.config` gets the
/// decomposed structure; every other setting is a single scalar value.
MergeStrategy strategyForSettingKey(String? key) =>
    key == 'app.config' ? configStrategy : scalarStrategy;
