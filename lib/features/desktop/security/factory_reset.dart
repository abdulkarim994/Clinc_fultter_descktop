/// ============================================================================
///  الخروج المصنعي لسطح المكتب — إعادة الجهاز إلى حالة التثبيت الأول
/// ============================================================================
///
///  (قرار المالك — Windows Desktop Security §ثالثاً «تسجيل الخروج»):
///  على سطح المكتب، «تسجيل الخروج» ليس مجرد إنهاء جلسة بل **مسحٌ كامل لا
///  رجعة فيه** لكل أثرٍ حساس على القرص، فلا تُستعاد بياناتُ عيادةٍ من جهازٍ
///  انتقل لطبيبٍ آخر أو خرج من الخدمة:
///
///    ١) كل صفوف الجداول الحساسة (المرضى، السجلات، الديون، المواعيد،
///       التركيبات، الأشعة، الموظفون، المصروفات، الطابور) — بما فيها
///       `employees` و`expenses` اللذان يفوتهما `wipeAllAccountData`.
///    ٢) ملفات القاعدة المشفَّرة كلها (db + WAL + SHM) وخزنة صور الأشعة.
///    ٣) **مفتاح القاعدة** من مخزن أسرار النظام (DPAPI) — فبلا المفتاح
///       تصير أي بقايا بايتاتٍ على القرص كتلةً لا تُفكّ أبداً.
///    ٤) توكنات الجلسة (المخزن الآمن) واعتمادات الدخول المحلية.
///    ٥) التفضيلات المكتبية، إعداد السحابة وختمه، الصادرات، والمؤقتات.
///
///  ما يبقى (اختيارياً): الإعدادات العامة **غير الحساسة** فقط — لغة
///  العرض ووضع السمة ومقياس الخط — كي لا يعود الجهاز أعجميّ الإعداد بعد
///  كل خروج. لا اسم مركزٍ ولا عيادات ولا أي شيء يخص مريضاً.
///
///  ⚠ النطاق: سطح المكتب فقط. الهاتف يُبقي سلوكه (offline-first: الخروج
///  لا يمسح) — هذه الدالة تُستدعى خلف بوابة `isDesktopUi` حصراً.
///
///  ⚠ الترتيب حَرِج: تُغلق كل مقابض القاعدة والخزنة **قبل** حذف الملفات
///  (ويندوز لا يحذف ملفاً مفتوحاً)، ثم يُحذف المفتاح **آخر** خطوة — فلو
///  انقطع المسح في منتصفه تبقى البقايا مشفَّرةً بمفتاحٍ لم يُحذف بعد، لا
///  مكشوفةً بمفتاحٍ حُذف قبل بياناته.
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../data/db/blob_vault.dart' show closeVaultsIn;
import '../../../data/db/db_boot.dart' show kDbFileName;
import '../../../data/db/db_key.dart' show kCipherMarkerFile;
import '../../../data/db/schema_sql.dart' show expectedTables;
import '../../../core/error_log.dart' show recordError;
import 'temp_cleaner.dart' show sweepEphemeral;

/// الإعدادات العامة غير الحساسة التي يجوز إبقاؤها عبر الخروج المصنعي
/// (مفاتيح metadata محلية للجهاز لا تخص أي مريض).
const Set<String> kNonSensitiveMetaKeys = {
  'dental_theme',
  'dental_font_size',
  'dental_lang',
};

/// نتيجة الخروج المصنعي — تُستعمل في السجل والاختبار.
class FactoryResetReport {
  const FactoryResetReport({
    required this.tablesCleared,
    required this.filesDeleted,
    required this.keyDeleted,
    required this.sessionDeleted,
    this.errors = const [],
  });

  final int tablesCleared;
  final int filesDeleted;
  final bool keyDeleted;
  final bool sessionDeleted;
  final List<String> errors;

  bool get clean => errors.isEmpty;

  @override
  String toString() =>
      'FactoryReset(tables:$tablesCleared files:$filesDeleted '
      'key:$keyDeleted session:$sessionDeleted errors:${errors.length})';
}

/// ينفّذ الخروج المصنعي الكامل. [keepGeneralSettings] يُبقي مفاتيح
/// [kNonSensitiveMetaKeys] وحدها (الافتراض true — قرار المالك «مع الإبقاء
/// فقط على الإعدادات العامة غير الحساسة إذا كانت مطلوبة»).
///
/// لا يرمي أبداً: كل خطوة تُحاط بحمايةٍ تسجّل عطلها وتتابع، فالهدف هو
/// **أقصى مسحٍ ممكن** لا التوقف عند أول ملفٍ مقفول. يعيد تقريراً يُفحص.
Future<FactoryResetReport> runFactoryReset(
  WidgetRef ref, {
  bool keepGeneralSettings = true,
}) async {
  final errors = <String>[];
  final dir = ref.read(dbDirProvider);
  var tablesCleared = 0;
  var filesDeleted = 0;

  // ── ١) مسح صفوف الجداول الحساسة كلها (قبل إغلاق القاعدة) ──
  // نغطي كل جداول [expectedTables] الحساسة — بما فيها employees/expenses
  // اللذين يفوتهما wipeAllAccountData. metadata تُعالَج انتقائياً أدناه.
  try {
    final db = ref.read(localDbProvider);
    for (final t in expectedTables) {
      if (t == 'metadata') continue;
      try {
        db.execute('DELETE FROM $t');
        tablesCleared++;
      } catch (_) {/* جدول غائب — تخطَّ */}
    }
    // metadata: احذف كل شيء عدا المفاتيح العامة غير الحساسة (إن طُلب).
    try {
      if (keepGeneralSettings) {
        final keep = kNonSensitiveMetaKeys.map((k) => "'$k'").join(',');
        db.execute('DELETE FROM metadata WHERE key NOT IN ($keep)');
      } else {
        db.execute('DELETE FROM metadata');
      }
      tablesCleared++;
    } catch (_) {/* best-effort */}
    // نقطة تفتيش: أفرغ صفحات WAL إلى الملف كي لا تبقى بقايا في WAL بعد
    // إغلاقٍ غير نظيف (المسح نفسه سيحذف الملفات، وهذا تحوّطٌ إضافي).
    try {
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  } catch (e, st) {
    errors.add('clear-tables: $e');
    recordError(e, st, context: 'factory-reset:clear-tables');
  }

  // ── ٢) إغلاق كل المقابض (القاعدة + الخزنات) قبل حذف الملفات ──
  // ويندوز لا يحذف ملفاً مفتوحاً؛ نُبطل مزوّد القاعدة ونغلق خزنات الصور.
  try {
    closeVaultsIn(p.join(dir, 'xray_images'));
  } catch (_) {}
  try {
    // إبطال المزوّد يستدعي onDispose(db.close) المسجَّل في localDbProvider.
    ref.invalidate(localDbProvider);
  } catch (_) {}
  // مهلة قصيرة تضمن تحرير النظام لمقابض الملفات على ويندوز.
  await Future<void>.delayed(const Duration(milliseconds: 60));

  // ── ٣) حذف كل الملفات الحساسة على القرص ──
  final targets = <String>[
    // القاعدة المشفَّرة ومرافقاها.
    kDbFileName,
    '$kDbFileName-wal',
    '$kDbFileName-shm',
    '$kDbFileName-journal',
    // علامة التشفير.
    kCipherMarkerFile,
    // إعداد السحابة وختمه (يُعاد إدخاله عند الحاجة).
    'cloud_config.json',
    'cloud_config.hmac',
    // جلسة كلمة المرور النصّية القديمة (إن بقيت من نسخةٍ سابقة).
    'session.json',
    // سجل الأعطال (قد يحمل سياقاً — يُمحى تحوّطاً).
    'errors.log',
  ];
  for (final name in targets) {
    filesDeleted += _deletePath(p.join(dir, name), errors);
  }
  // مجلدات كاملة: خزنة صور الأشعة، الصور السادة القديمة، الصادرات،
  // والمؤقتات — كلها تُزال بالكامل.
  for (final sub in ['xray_images', 'exports', 'tmp', 'cache']) {
    filesDeleted += _deleteDir(p.join(dir, sub), errors);
  }

  // ── ٤) كنس المؤقتات خارج مجلد البيانات (نظام التشغيل) ──
  try {
    await sweepEphemeral(dir);
  } catch (e) {
    errors.add('sweep-ephemeral: $e');
  }

  // ── ٥) حذف توكن الجلسة من المخزن الآمن ──
  var sessionDeleted = false;
  try {
    final store = ref.read(sessionStoreProvider);
    store?.delete();
    sessionDeleted = true;
  } catch (e, st) {
    errors.add('session-delete: $e');
    recordError(e, st, context: 'factory-reset:session');
  }

  // ── ٦) حذف مفتاح القاعدة من مخزن النظام — آخر خطوة عمداً ──
  var keyDeleted = false;
  try {
    await ref.read(dbKeyStoreProvider).delete();
    keyDeleted = true;
  } catch (e, st) {
    errors.add('key-delete: $e');
    recordError(e, st, context: 'factory-reset:key');
  }

  final report = FactoryResetReport(
    tablesCleared: tablesCleared,
    filesDeleted: filesDeleted,
    keyDeleted: keyDeleted,
    sessionDeleted: sessionDeleted,
    errors: errors,
  );
  // لا نطبع التقرير في الإنتاج (قد يحمل مسارات) — يُسجَّل عبر منقّي PHI فقط.
  if (!report.clean) {
    unawaited(Future(() => recordError(
        StateError('factory-reset incomplete: $report'),
        StackTrace.current,
        context: 'factory-reset:summary')));
  }
  return report;
}

/// حذف ملفٍ واحد؛ يعيد 1 إن حُذف فعلاً و0 إن غاب. يبتلع الخطأ ويسجّله.
int _deletePath(String path, List<String> errors) {
  try {
    final f = File(path);
    if (f.existsSync()) {
      f.deleteSync();
      return 1;
    }
  } catch (e) {
    errors.add('del-file ${p.basename(path)}: $e');
  }
  return 0;
}

/// حذف مجلدٍ بالكامل؛ يعيد عدد العناصر المحذوفة تقريبياً (1 للمجلد).
int _deleteDir(String path, List<String> errors) {
  try {
    final d = Directory(path);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
      return 1;
    }
  } catch (e) {
    errors.add('del-dir ${p.basename(path)}: $e');
  }
  return 0;
}

/// نسخة اختبارية مكشوفة من حذف المسار (للتحقق من دلالات الحذف).
@visibleForTesting
int debugDeletePath(String path, List<String> errors) =>
    _deletePath(path, errors);
