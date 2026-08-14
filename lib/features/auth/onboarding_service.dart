/// منطق الإعداد الإلزامي لأول مرة + مسح بيانات الحساب — التوأم الحرفي لـ
/// services/onboarding.service.js (+ دلالات clearLocalData للتبديل).
///
/// القاعدة (حالة + صحة بيانات معاً): الإعداد مكتمل ⇔ (بيانات الحساب صحيحة)
/// **و** (علم الإكمال مضبوط لهذا الـ uid). صحة البيانات هي الحارس الرئيسي:
/// بيانات ناقصة ⇒ غير مكتمل مهما كان العلم؛ بيانات صحيحة وعلم غير مضبوط
/// (حساب قديم) ⇒ ترحيل: نضبط العلم تلقائياً فلا نحبس مكتملاً بالخطأ.
library;

import '../../data/db/local_db.dart';
import '../../data/db/schema_sql.dart' show migrationTables;

typedef JMap = Map<String, Object?>;

/// م180/٦ — اسم العلامة التجارية (بديل «طب الأسنان الرقمي» في كل التطبيق).
const kAppBrandName = 'DENTSHINE';

/// اسم المركز الافتراضي — لا يُعدّ إعداداً صحيحاً (توأم DEFAULT_CONFIG).
///
/// م180/٦ — **قيمتان لا واحدة**: الاسم الجديد والقديم معاً. حسابٌ قديم
/// اسمُ مركزه «طب الأسنان الرقمي» (الافتراضي وقتها) يجب أن يبقى **غير
/// مكتمل الإعداد** كما كان — ولو حذفنا القديمة لاعتُبر مكتملاً خطأً
/// ودخل التطبيق باسمٍ نائب.
const defaultCenterName = kAppBrandName;
const legacyDefaultCenterName = 'طب الأسنان الرقمي';

/// هل بيانات الحساب صحيحة؟ اسم مركز حقيقي (غير فارغ وغير الافتراضي) +
/// عيادة واحدة على الأقل — isAccountConfigured حرفياً.
bool isAccountConfigured(Map<String, Object?>? config) {
  if (config == null) return false;
  final name = '${config['centerName'] ?? ''}'.trim();
  final clinics = [
    for (final c in (config['clinics'] as List? ?? const []))
      if ('$c'.trim().isNotEmpty) '$c',
  ];
  final nameOk = name.isNotEmpty &&
      name != defaultCenterName &&
      name != legacyDefaultCenterName;
  return nameOk && clinics.isNotEmpty;
}

String _flagKey(String uid) => 'dental_setup_complete:$uid';
const _lastUidKey = 'dental_last_uid';

/// علم الإكمال الدائم لكل uid — مخزَّن في metadata (device-local، لا يُزامن)
/// توأم localStorage per-uid.
bool isSetupFlagSet(LocalDb db, String? uid) {
  if (uid == null || uid.isEmpty) return false;
  final row = db.queryFirst(
      'SELECT value FROM metadata WHERE key = ?', [_flagKey(uid)]);
  return '${row?['value'] ?? ''}' == '1';
}

void markSetupComplete(LocalDb db, String? uid) {
  if (uid == null || uid.isEmpty) return;
  db.execute(
      "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
      "VALUES (?, '1', datetime('now'))",
      [_flagKey(uid)]);
}

void clearSetupComplete(LocalDb db, String? uid) {
  if (uid == null || uid.isEmpty) return;
  db.execute('DELETE FROM metadata WHERE key = ?', [_flagKey(uid)]);
}

/// القرار النهائي (يعتمد على الحالة + صحة البيانات): بيانات ناقصة ⇒ غير
/// مكتمل؛ بيانات صحيحة وعلم غير مضبوط ⇒ ترحيل (نضبط العلم) ونعتبره مكتملاً.
bool isSetupComplete(LocalDb db, String? uid, Map<String, Object?>? config) {
  if (!isAccountConfigured(config)) return false;
  if (!isSetupFlagSet(db, uid)) markSetupComplete(db, uid);
  return true;
}

// ── تبديل الحساب ومسح بياناته (دلالات clearLocalData) ───────────────────────

String? lastUid(LocalDb db) {
  final row = db.queryFirst(
      'SELECT value FROM metadata WHERE key = ?', const [_lastUidKey]);
  final v = '${row?['value'] ?? ''}';
  return v.isEmpty ? null : v;
}

void setLastUid(LocalDb db, String? uid) {
  db.execute(
      "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
      "VALUES (?, ?, datetime('now'))",
      [_lastUidKey, uid ?? '']);
}

/// م33 — تعافي الملكية الذاتي (علة «بيانات الحساب القديم تظهر عند الفتح»):
/// الصفوف القديمة كُتبت **بلا ختم مالك** وعبارة العزل تقبلها لأي حساب،
/// وتتبّع «آخر حساب» لم يكن موجوداً في الدخولات القديمة فالتبديل لا
/// يُكشف. عند أول إقلاع/دخول بلا آخر-حساب مسجل:
///   • cloud: الصفوف المتسخة بلا مالك (تعديلات غير مدفوعة لجلستك) تُختم
///     بالحساب الحالي حمايةً لها؛ النظيفة بلا مالك وصفوف الحسابات الأخرى
///     تُمسح؛ ويُصفَّر مؤشر السحب فتُعاد البيانات الحقيقية من الخادم
///     (مسار السحب-أولاً م18).
///   • local (بلا سحابة): لا خادم يعوّض — تُختم كل الصفوف بلا مالك
///     بالحساب الحالي (جهاز مستخدم واحد) ولا يُمسح شيء.
/// ثم يسجَّل آخر حساب فلا يعود المسار «مجهول المصدر» أبداً.
/// [claimDirty]: عند **استعادة الجلسة** (نفس الجلسة التي كتبت الصفوف)
/// تُختم المتسخة بلا مالك حمايةً؛ عند **دخول جديد** لا استمرارية جلسة —
/// قد تعود لحساب سابق — فتُمسح مع النظيفة (الخادم يعوّض بيانات الحساب).
void healOwnershipAtBoot(
  LocalDb db,
  String uid, {
  required bool cloud,
  bool claimDirty = true,
}) {
  if (uid.isEmpty) return;
  for (final t in migrationTables) {
    try {
      if (cloud) {
        if (claimDirty) {
          db.execute(
              'UPDATE $t SET owner_uid = ? '
              'WHERE owner_uid IS NULL AND _dirty = 1',
              [uid]);
        }
        db.execute(
            'DELETE FROM $t WHERE owner_uid IS NULL '
            'OR (owner_uid IS NOT NULL AND owner_uid <> ?)',
            [uid]);
      } else {
        db.execute(
            'UPDATE $t SET owner_uid = ? WHERE owner_uid IS NULL',
            [uid]);
      }
    } catch (_) {/* جدول بلا هذه الأعمدة — تخطَّ */}
  }
  if (cloud) {
    // تصفير مؤشر السحب ⇒ الدورة التالية تسحب بيانات الحساب كاملة.
    try {
      db.execute(
          "DELETE FROM metadata WHERE key = 'sync.cursor.txid'");
    } catch (_) {/* best-effort */}
  }
  setLastUid(db, uid);
}

/// مسح **كامل** لبيانات الحساب المحلية — يُستدعى عند دخول حساب **مختلف**
/// (كشف التبديل السلطوي في الأصل): الجداول الثمانية + مؤشر السحب + الظلال
/// + الحجر الصحي + طوابير الصور، فلا تتسرب بيانات حساب سابق. لا يمس ملفات
/// صور الأشعة على القرص (يتكفل بها المستدعي عبر XrayStore عند اللزوم).
void wipeAllAccountData(LocalDb db) {
  for (final t in migrationTables) {
    try {
      db.execute('DELETE FROM $t');
    } catch (_) {/* جدول غائب — تخطَّ */}
  }
  // إصلاح ثغرة تسرّب: `migrationTables` ثمانيةٌ فقط ويفوتها جدولا
  // `employees` (رواتب الموظفين) و`expenses` (المصروفات) — وكلاهما
  // بياناتٌ ماليةٌ حساسة تخصّ الحساب. بلا مسحهما يرى الحساب الجديد
  // (بعد تبديلٍ سلطوي) رواتبَ ومصروفاتِ الحساب السابق. يُمسحان صراحةً.
  for (final t in ['employees', 'expenses']) {
    try {
      db.execute('DELETE FROM $t');
    } catch (_) {/* جدول غائب — تخطَّ */}
  }
  for (final t in ['conflict_log', 'sync_meta', 'sync_queue',
    'pending_uploads']) {
    try {
      db.execute('DELETE FROM $t');
    } catch (_) {/* اختياري */}
  }
  // مفاتيح المزامنة/الحُرّاس في metadata (المؤشر، الظلال، الحجر، الطوابير)
  // — نُبقي هوية الجهاز وساعة HLC وأعلام الإعداد per-uid.
  try {
    db.execute(
        "DELETE FROM metadata WHERE key LIKE 'sync.%' "
        "OR key LIKE 'shadow:%' "
        "OR key LIKE 'dental_%xray%' "
        "OR key LIKE 'dental_superseded%' "
        "OR key LIKE 'dental_deleted%' "
        "OR key LIKE 'xray.upload.reserved.%' "
        // إصلاح تبديل الحساب (حرج): حصة التخزين واستهلاكه المخبَّآن،
        // وتخبئة الرخصة — كلاهما per-account ولم يكونا ضمن أنماط المسح،
        // فيتسرّبان للحساب الجديد: مقياسٌ يعرض حصة الحساب السابق (فيرفع
        // الجديد الممتلئ)، ورخصةٌ تحكم بحقوق حسابٍ آخر. يُمسحان مع بياناته.
        "OR key LIKE 'xray.storage.%' "
        "OR key LIKE 'license.%' "
        // فتتراكم هاشات مرور **كل** حساب استُعمل على الجهاز إلى الأبد. على
        // لوحيّ عيادة مشترك هذا أرشيف اعتمادات. يُمسح مع بيانات الحساب.
        "OR key = 'local_auth_accounts' "
        "OR key = 'local_auth_session'");
  } catch (_) {/* best-effort */}
}
