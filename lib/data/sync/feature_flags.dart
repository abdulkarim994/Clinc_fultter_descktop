/// ============================================================================
///  Sync feature flags — functional port of services/sync/featureFlags.js
/// ============================================================================
///
///  The original layers env parsing + localStorage overrides + staged rollout
///  on top of boolean gates. The Dart port keeps the same GATES and semantics
///  (per-entity override → rollout set → global default) with programmatic
///  setters instead of Vite env/localStorage plumbing.
///
///  Defaults mirror the original's production defaults:
///    • SYNC_V2            : ON  (the delta engine is the wired path)
///    • FIELD_MERGE global : OFF — لكن قائمة الطرح FIELD_MERGE_ROLLOUT
///      **مشحونة في مصدر الأصل مفعّلة للكيانات الثمانية كلها** (بما فيها
///      `settings`)، فالدمج الحقلي/البنيوي هو المسار الإنتاجي الفعلي —
///      انظر featureFlags.js §Commit 4 وthe rollout const at line ~400.
///      م18: نقلُها فارغةً كان علة «إعدادات الحساب وخطط العلاج لا تظهر»:
///      أي كتابة إعدادات محلية قبل أول سحب تجعل LWW بالقيمة الكاملة يحجب
///      config الحساب نزولاً (kept-local) ويمسحه دفعاً.
///    • FIELD_MERGE_VERIFY : OFF (dual-run divergence logging)
///    • PHONE_IDENTITY     : OFF (legacy TRIM(name) patient keys)
///    • COLD_FETCH         : OFF (server augmentation of sparse searches)
library;

/// قائمة الطرح الإنتاجية — التوأم الحرفي لـ FIELD_MERGE_ROLLOUT في
/// featureFlags.js (كل كيان أُدرج هناك بعد نجاح حزمته الخاصة):
/// `new Set(['patients','appointments','xrays','records','prosthetics',
///           'debts','queue_patients','settings'])`
const Set<String> kFieldMergeRolloutDefault = {
  'patients',
  'appointments',
  'xrays',
  'records',
  'prosthetics',
  'debts',
  'queue_patients',
  'settings',
};

class SyncFlags {
  /// م-عزل الهوية — **الافتراضي ON** (كان OFF حرفيةً للأصل): البناء
  /// السحابي (build_cloud.sh) يمرّر PHONE_IDENTITY=1 أصلاً، فبياناتُ
  /// الإنتاج مكتوبةٌ بمفاتيح الهوية p:هاتف:اسم؛ توحيدُ الافتراضي معها
  /// يمنع تشغيل عميلٍ يفصم الهوية. `resetForTest` يبقى OFF عمداً كخطّ
  /// أساسٍ للاختبارات القديمة (مفاتيح TRIM(name) الموروثة).
  bool phoneIdentity = true;
  bool coldFetch = false;

  /// Phase H — CLINIC_XRAY_ISOLATION: يغيّر **القراءة فقط** (معرض أشعة
  /// المريض داخل عيادة يعرض صورها الموسومة بها + القديمة غير الموسومة —
  /// لا فقد صور أبداً). وسم البيانات نفسه دائم التفعيل.
  /// م35 — **قرار مالك v12**: العزل الكامل بالعيادة مفعّل افتراضياً
  /// (كان مطفأً حرفيةً للأصل قبل القرار).
  bool clinicXrayIsolation = true;

  bool syncV2 = true;


  /// Global field-merge default (row entities + settings/app.config).
  bool fieldMerge = false;

  /// Dual-run verify mode: legacy result applied, divergences logged.
  bool fieldMergeVerify = false;

  /// Gradual rollout stage: entities force-enabled regardless of the global —
  /// تُشحن بقائمة الإنتاج (توأم الثابت FIELD_MERGE_ROLLOUT في الأصل).
  final Set<String> fieldMergeRollout = <String>{...kFieldMergeRolloutDefault};

  /// Explicit per-entity overrides — win over rollout AND global
  /// (including `false` = instant rollback, exactly like the LS override).
  final Map<String, bool> fieldMergeOverride = <String, bool>{};

  void resetForTest() {
    phoneIdentity = false;
    coldFetch = false;
    clinicXrayIsolation = true; // م35 — قرار مالك: العزل الافتراضي

    syncV2 = true;
    fieldMerge = false;
    fieldMergeVerify = false;
    // «إعادة الضبط» تعيد وضع الشحن الإنتاجي نفسه (لا صفراً مطلقاً) — كما
    // يعود متصفح بلا تجاوزات localStorage إلى قائمة الطرح المشحونة.
    fieldMergeRollout
      ..clear()
      ..addAll(kFieldMergeRolloutDefault);
    fieldMergeOverride.clear();
  }

  /// وضع ما-قبل-الطرح (اختبارات المسار القديم LWW حصراً): يفرغ قائمة
  /// الطرح ويطفئ الدمج الحقلي — يكافئ `FIELD_MERGE_&lt;ENTITY&gt;=0` للجميع.
  void disableFieldMergeForTest() {
    fieldMerge = false;
    fieldMergeVerify = false;
    fieldMergeRollout.clear();
    fieldMergeOverride.clear();
  }
}

final SyncFlags syncFlags = SyncFlags();

bool isPhoneIdentityEnabled() => syncFlags.phoneIdentity;
bool isColdFetchEnabled() => syncFlags.coldFetch;

/// Phase H — المعرض المعزول بالعيادة (الافتراضي مطفأ؛ الوسم دائم).
bool isClinicXrayIsolationEnabled() => syncFlags.clinicXrayIsolation;
bool isSyncV2Enabled() => syncFlags.syncV2;

/// Per-entity gate: explicit override wins, then rollout stage, then global.
bool isFieldMergeEnabled([String? entity]) {
  if (entity != null) {
    final per = syncFlags.fieldMergeOverride[entity];
    if (per != null) return per;
    if (syncFlags.fieldMergeRollout.contains(entity)) return true;
  }
  return syncFlags.fieldMerge;
}

bool isFieldMergeVerifyEnabled() => syncFlags.fieldMergeVerify;
